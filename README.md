# ActiveStorage Issue

```ruby
ApplicationRecord.connected_to(role: :writing, shard: :default) do
   random_file = Tempfile.new('random_file.txt')
   random_file.write(SecureRandom.hex(10))
   random_file.rewind

   product.create!(file: {
      io: File.open(random_file.path),
      filename: 'random_file.txt',
      content_type: 'text/plain'
   })
end
```

Here not works

```ruby
ApplicationRecord.connected_to(role: :writing, shard: :sharded) do
   random_file = Tempfile.new('random_file.txt')
   random_file.write(SecureRandom.hex(10))
   random_file.rewind

   product.create!(file: {
      io: File.open(random_file.path),
      filename: 'random_file.txt',
      content_type: 'text/plain'
   })
end
```