# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "rails", "8.1.1"
  # If you want to test against edge Rails replace the previous line with this:
  # gem "rails", github: "rails/rails", branch: "main"

  gem "pg"
end

require "active_record/railtie"
require "active_storage/engine"
require "minitest/autorun"
require "tempfile"
require "securerandom"
require "fileutils"

# Setup databases
ENV["PRIMARY_DATABASE_URL"] = "postgresql://postgres@localhost/activestorage_sharding_test_primary"
ENV["SHARD_DATABASE_URL"] = "postgresql://postgres@localhost/activestorage_sharding_test_shard"

class TestApp < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f

  config.root = __dir__
  config.hosts << "example.org"
  config.eager_load = false
  config.session_store :cookie_store, key: "cookie_store_key"
  config.secret_key_base = "secret_key_base"

  config.logger = Logger.new($stdout)
  Rails.logger  = config.logger
  config.active_storage.variant_processor = :disabled
  config.active_storage.service = :test
  config.active_storage.service_configurations = {
    test: {
      service: "Disk",
      root: File.join(Dir.tmpdir, "activestorage_sharding_test")
    }
  }

  config.active_job.queue_adapter = :inline
end

Rails.application.initialize!

# Setup database connections with sharding
base_config = {
    "primary" => {
      "adapter" => "postgresql",
      "encoding" => "unicode",
      "database" => "activestorage_sharding_test_primary",
      "username" => "postgres",
      "password" => "",
      "host" => "localhost"
    },
    "primary_shard_one" => {
      "adapter" => "postgresql",
      "encoding" => "unicode",
      "database" => "activestorage_sharding_test_shard",
      "username" => "postgres",
      "password" => "",
      "host" => "localhost"
    }
}
ActiveRecord::Base.configurations = {
  "test" => base_config,
  "development" => base_config,
}

# Drop and recreate databases
def recreate_database(db_name)
  config = {
    adapter: "postgresql",
    encoding: "unicode",
    username: "postgres",
    password: "",
    host: "localhost"
  }

  admin_config = config.merge(database: "postgres")
  ActiveRecord::Base.establish_connection(admin_config)

  # Drop database if exists
  ActiveRecord::Base.connection.execute("DROP DATABASE IF EXISTS #{db_name}")
  puts "Database '#{db_name}' dropped."

  # Create database
  ActiveRecord::Base.connection.execute("CREATE DATABASE #{db_name}")
  puts "Database '#{db_name}' created."
end

recreate_database("activestorage_sharding_test_primary")
recreate_database("activestorage_sharding_test_shard")

# Reconnect to primary
primary_config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary")
ActiveRecord::Base.establish_connection(primary_config.configuration_hash)

# Configure shards
ActiveRecord::Base.connects_to shards: {
  primary: { writing: :primary },
  sharded: { writing: :primary_shard_one }
}

# Load ActiveStorage migrations
require ActiveStorage::Engine.root.join("db/migrate/20170806125915_create_active_storage_tables.rb").to_s

# Create schema in both databases
ActiveRecord::Schema.define do
  CreateActiveStorageTables.new.change

  create_table :products, force: true do |t|
    t.string :title
    t.timestamps
  end
end

# Create tables in sharded database
ActiveRecord::Base.connected_to(role: :writing, shard: :sharded) do
  ActiveRecord::Schema.define do
    CreateActiveStorageTables.new.change

    create_table :products, force: true do |t|
      t.string :title
      t.timestamps
    end
  end
end

module StoragePathable
  extend ActiveSupport::Concern

  included do
    before_create :assign_subdomain_to_attachments

    def assign_subdomain_to_attachments
      self.class.reflect_on_all_attachments.each do |reflection|
        attachment = public_send(reflection.name)
        next unless attachment.attached?

        original_key = attachment.blob.key
        # Add tenant/model prefix to key
        prefix = [['tenant_a', 'tenant_b', 'tenant_c'].sample, self.class.name.underscore.pluralize].compact.join('/')

        unless original_key.start_with?(prefix)
          new_key = "#{prefix}/#{original_key}"
          attachment.blob.key = new_key
        end
      end
    end
  end
end

# Models
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # Only adding this cause error
  connects_to shards: {
    primary: { writing: :primary },
    sharded: { writing: :primary_shard_one }
  }
end

class Product < ApplicationRecord
  include StoragePathable
  has_one_attached :file
end

# Ensure storage directory exists
FileUtils.rm_rf(ActiveStorage::Blob.service.root)
FileUtils.mkdir_p(ActiveStorage::Blob.service.root)

class BugTest < ActiveSupport::TestCase
  def setup
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)
    FileUtils.mkdir_p(ActiveStorage::Blob.service.root)
  end

  def test_normal_shard_file_existence
    product = nil
    ApplicationRecord.connected_to(role: :writing, shard: :primary) do
      random_file = Tempfile.new('random_file.txt')
      random_file.write(SecureRandom.hex(10))
      random_file.rewind

      product = Product.create!(
        title: 'Product Primary',
        file: {
          io: File.open(random_file.path),
          filename: 'random_file.txt',
          content_type: 'text/plain'
        }
      )
    end

    # This works - file exists on disk
    assert File.exist?(ActiveStorage::Blob.service.path_for(product.file.blob.key)),
      "File should exist on disk for primary shard"
  end

  def test_sharded_database_file_existence
    product = nil
    ApplicationRecord.connected_to(role: :writing, shard: :sharded) do
      random_file = Tempfile.new('random_file.txt')
      random_file.write(SecureRandom.hex(10))
      random_file.rewind

      product = Product.create!(
        title: 'Product Sharded',
        file: {
          io: File.open(random_file.path),
          filename: 'sharded_random_file.txt',
          content_type: 'text/plain'
        }
      )
    end

    # BUG: This fails - file doesn't exist on disk when using sharded database
    # The blob is created but the file is not uploaded to storage
    ApplicationRecord.connected_to(role: :writing, shard: :sharded) do
      file_path = ActiveStorage::Blob.service.path_for(product.file.blob.key)
      puts "Expected file at: #{file_path}"
      puts "File exists: #{File.exist?(file_path)}"

      assert File.exist?(file_path),
        "File should exist on disk for sharded database, but it doesn't!"
    end
  end
end
