require 'bundler/setup'

# Set the environment first
ENV['RAILS_ENV'] ||= 'test'

require 'active_record'
require 'tempfile'
require 'securerandom'
require 'fileutils'
require 'yaml'

# Ensure storage directory exists
FileUtils.mkdir_p('./tmp/storage')
FileUtils.mkdir_p('./config')

# Load Rails and ActiveStorage
require 'rails'
require 'active_storage/engine'

# Load custom service
require_relative 'lib/active_storage/service/custom_disk_service'

# Create a minimal Rails application
class TestApp < Rails::Application
  config.load_defaults 7.2
  config.eager_load = false
  config.root = Pathname.new('.')

  # Configure ActiveStorage
  config.active_storage.service = :test
  config.active_storage.service_configurations = {
    test: {
      service: "CustomDisk",
      root: "./tmp/storage"
    }
  }

  # Provide database configuration programmatically
  config.before_initialize do
    # Set database configuration path to nil to avoid looking for database.yml
    config.paths.add "config/database", with: "config/database.yml"

    # Define database configurations
    db_config = {
      "test" => {
        "primary" => {
          adapter: "postgresql",
          encoding: "unicode",
          database: "postgres",
          username: "postgres",
          password: "",
          host: "postgres",
        },
        "primary_shard_one" => {
          adapter: "postgresql",
          encoding: "unicode",
          database: "postgres_shard",
          username: "postgres",
          password: "",
          host: "postgres",
        }
      }
    }

    # Write a temporary database.yml file
    File.write("config/database.yml", db_config.to_yaml)
  end
end

# Initialize the Rails application
Rails.application.initialize!

# Create databases if they don't exist
def create_database_if_not_exists(db_name, config)
  begin
    test_config = config.merge('database' => db_name)
    ActiveRecord::Base.establish_connection(test_config)
    ActiveRecord::Base.connection.execute('SELECT 1')
    puts "Database '#{db_name}' already exists."
  rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
    # Connect to template1 database to create the new database
    admin_config = config.merge('database' => 'template1')
    ActiveRecord::Base.establish_connection(admin_config)

    # Check if database exists before creating
    result = ActiveRecord::Base.connection.execute(
      "SELECT 1 FROM pg_database WHERE datname = '#{db_name}'"
    )

    if result.count == 0
      ActiveRecord::Base.connection.execute("CREATE DATABASE #{db_name}")
      puts "Database '#{db_name}' created."
    else
      puts "Database '#{db_name}' already exists."
    end
  end
end

# Get base configuration
base_config = {
  'adapter' => 'postgresql',
  'encoding' => 'unicode',
  'username' => 'postgres',
  'password' => '',
  'host' => 'postgres'
}

# Create both databases
create_database_if_not_exists('postgres', base_config)
create_database_if_not_exists('postgres_shard', base_config)

# Reconnect to primary
primary_config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary").configuration_hash
ActiveRecord::Base.establish_connection(primary_config)

# Configure shards after initialization
ActiveRecord::Base.connects_to shards: {
  default: { writing: :primary },
  sharded: { writing: :primary_shard_one }
}

# Migrations
class CreateProductTable < ActiveRecord::Migration[7.2]
  def change
    create_table :products do |t|
      t.string :title

      t.timestamps
    end
  end
end

class CreateActiveStorageTables < ActiveRecord::Migration[7.2]
  def change
    create_table :active_storage_blobs do |t|
      t.string   :key,          null: false
      t.string   :filename,     null: false
      t.string   :content_type
      t.text     :metadata
      t.string   :service_name, null: false
      t.bigint   :byte_size,    null: false
      t.string   :checksum

      t.datetime :created_at, null: false

      t.index [:key], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false
      t.references :blob,     null: false

      t.datetime :created_at, null: false

      t.index [:record_type, :record_id, :name, :blob_id], name: :index_active_storage_attachments_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, index: false
      t.string :variation_digest, null: false

      t.index [:blob_id, :variation_digest], name: :index_active_storage_variant_records_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
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
        # Get prefix - hardcoded for this example
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
end

class Product < ApplicationRecord
  include StoragePathable

  has_one_attached :file
end
