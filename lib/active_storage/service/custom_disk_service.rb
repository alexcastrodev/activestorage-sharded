require 'active_storage/service/disk_service'

module ActiveStorage
  class Service
    class CustomDiskService < DiskService
        def path_for(key)
          tenant, model, actual_key = key.split('/', 3)
          prefix = "#{tenant}/#{model}"

          if actual_key
            # Sharding is the official way of path_for in ActiveStorage (disk_service)
            sharded = File.join([actual_key[0..1], actual_key[2..3]], actual_key)
            File.join(root, prefix, sharded)
          else
            super
          end
        end
    end
  end
end






