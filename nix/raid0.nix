{ nb_devices, lib, ... }: 
{
  disko.devices = {
    disk = lib.genAttrs (builtins.genList (f: "nvme${toString f}n1") nb_devices) 
    (name: 
      { type = "disk";
        device = "/dev/${name}";
        content = {
          type = "mdraid";
          name = "raid0";
        };
      }
    );
    mdadm = {
      raid0 = {
        type = "mdadm";
        level = 0;
      };
    };
  };
}
