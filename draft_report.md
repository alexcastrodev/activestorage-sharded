### Steps to reproduce

```ruby
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
```

Full code example to reproduce the issue: 

### Expected behavior
Same behaviour as non-sharded (or primary) database - file should exist on disk after upload.
After save! should trigger upload to storage.

### Actual behavior
After save! does not upload the file to storage when using a sharded database connection.

### Additional information
After some investigation, i see that this piece of code shows `attachment_changes` as empty hash `{}` in sharded database context:

```
after_commit(on: %i[ create update ]) { attachment_changes.delete(name.to_s).try(:upload) }
```

Output:

```bash
Accessing attachment_changes for record id: 1 {}
After commit for preview_image on record id: 1 {}
```

And it does not trigger the upload method, so the file is never uploaded to disk.

Otherwise, in the primary database context, attachment_changes shows the expected change:

```bash
Accessing attachment_changes for record id: 1 {"file"=>#<ActiveStorage::Attached::Changes::CreateOne:0x0000ffff79971ef8 @attachable={:io=>#<File:/tmp/random_file.txt20251112-19813-qfir2p>, :filename=>"random_file.txt", :content_type=>"text/plain"}, @record=#<Product id: 1, title: "Product Default", created_at: "2025-11-12 14:34:19.064333000 +0000", updated_at: "2025-11-12 14:34:19.096800000 +0000">, @name="file", @blob=#<ActiveStorage::Blob id: 1, key: "tenant_c/products/myzs4beve0efy8nim3u6o7c0kapv", filename: "random_file.txt", content_type: "text/plain", metadata: {"identified"=>true}, service_name: "test", byte_size: 20, checksum: "+vOKQqx/q6wwwyz8Xf6bBA==", created_at: "2025-11-12 14:34:19.094920000 +0000">, @attachment=#<ActiveStorage::Attachment id: 1, name: "file", record_type: "Product", record_id: 1, blob_id: 1, created_at: "2025-11-12 14:34:19.095835000 +0000">>}
After commit for file on record id: 1 {"file"=>#<ActiveStorage::Attached::Changes::CreateOne:0x0000ffff79971ef8 @attachable={:io=>#<File:/tmp/random_file.txt20251112-19813-qfir2p>, :filename=>"random_file.txt", :content_type=>"text/plain"}, @record=#<Product id: 1, title: "Product Default", created_at: "2025-11-12 14:34:19.064333000 +0000", updated_at: "2025-11-12 14:34:19.096800000 +0000">, @name="file", @blob=#<ActiveStorage::Blob id: 1, key: "tenant_c/products/myzs4beve0efy8nim3u6o7c0kapv", filename: "random_file.txt", content_type: "text/plain", metadata: {"identified"=>true}, service_name: "test", byte_size: 20, checksum: "+vOKQqx/q6wwwyz8Xf6bBA==", created_at: "2025-11-12 14:34:19.094920000 +0000">, @attachment=#<ActiveStorage::Attachment id: 1, name: "file", record_type: "Product", record_id: 1, blob_id: 1, created_at: "2025-11-12 14:34:19.095835000 +0000">>}
```

I also checked on Opened / Closed issues about sharded databases, but all of them wants to shard the storage itself, but this is not the case here. It just stop calling upload, when i add `connects_to` on ApplicationRecord.

### System configuration
Devcontainer

**Rails version**: 
8.1.1

**Ruby version**: 
3.2.2