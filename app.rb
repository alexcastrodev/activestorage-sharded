# app.rb - ActiveStorage Sharding Tests

require_relative 'setup'
require 'minitest/autorun'

class CustomerTest < Minitest::Test
  def setup
    # Create tables in both databases
    CreateProductTable.migrate(:up)
    CreateActiveStorageTables.migrate(:up)

    # Also create tables in the sharded database
    ActiveRecord::Base.connected_to(role: :writing, shard: :sharded) do
      CreateProductTable.migrate(:up)
      CreateActiveStorageTables.migrate(:up)
    end
  end

  def teardown
    # Drop tables from both databases
    CreateActiveStorageTables.migrate(:down)
    CreateProductTable.migrate(:down)

    ActiveRecord::Base.connected_to(role: :writing, shard: :sharded) do
      CreateActiveStorageTables.migrate(:down)
      CreateProductTable.migrate(:down)
    end

    # Clean storage folder before each test
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)
    FileUtils.mkdir_p(ActiveStorage::Blob.service.root)
  end

  def test_normal_shard_and_file_existence
    ApplicationRecord.connected_to(role: :writing, shard: :default) do
      random_file = Tempfile.new('random_file.txt')
      random_file.write(SecureRandom.hex(10))
      random_file.rewind

      Product.create!(
        title: 'Product Default',
        file: {
          io: File.open(random_file.path),
          filename: 'random_file.txt',
          content_type: 'text/plain'
        }
      )

    end
    
    # check file existence
    assert File.exist?(ActiveStorage::Blob.service.path_for(Product.last.file.blob.key)), "File should exist on disk"
  end

  def test_shard_switching_and_file_existence
    ApplicationRecord.connected_to(role: :writing, shard: :sharded) do
      random_file = Tempfile.new('random_file.txt')
      random_file.write(SecureRandom.hex(10))
      random_file.rewind

      Product.create!(
        title: 'Product Sharded',
        file: {
          io: File.open(random_file.path),
          filename: 'random_file.txt',
          content_type: 'text/plain'
        }
      )
    end

    # check file existence again
    assert File.exist?(ActiveStorage::Blob.service.path_for(Product.last.file.blob.key)), "File should exist on disk"
  end
end
