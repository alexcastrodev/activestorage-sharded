# ActiveStorage Issue

When using Rails' horizontal sharding with ApplicationRecord.connected_to(role: :writing, shard: :sharded), the Active Storage's custom disk service fails to process file uploads. 

When you attempt to create a WhateverModel with an attached file within the shard context, the CustomDiskStorage service never reaches its path_for method.

what the heck...


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



```bash
.

Finished in 6.133218s, 0.3261 runs/s, 0.3261 assertions/s.
2 runs, 2 assertions, 0 failures, 0 errors, 0 skips
```
