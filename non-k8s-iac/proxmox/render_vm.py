import argparse
import json
from pathlib import Path
import re
import shlex


CREATE_OPTIONS = {
    "agent", "balloon", "bios", "cores", "cpu", "machine", "memory",
    "name", "net0", "onboot", "ostype", "scsihw", "sockets", "startup", "tags",
}
DEVICE_OPTIONS = {"boot", "efidisk0", "scsi0", "hostpci0", "usb0"}


def read_manifest(path):
    options = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        key, separator, value = line.partition(": ")
        if not separator or key not in CREATE_OPTIONS | DEVICE_OPTIONS or key in options:
            raise ValueError(f"{path}:{number}: invalid or duplicate option {key!r}")
        options[key] = value
    required = CREATE_OPTIONS | {"boot", "efidisk0", "scsi0"}
    if not required <= options.keys():
        raise ValueError(f"{path}: required VM options are missing")
    return options


def render_vm(host_path, vmid, disk_image=None):
    host_path = Path(host_path)
    host = json.loads(host_path.read_text())
    guest = host["guests"].get(str(vmid))
    if guest is None:
        raise ValueError(f"Unknown VMID {vmid}")
    options = read_manifest(host_path.parent / guest["manifest"])
    if options["name"] != guest["name"]:
        raise ValueError("Manifest name does not match host inventory")
    storage = host["hypervisor"]["vm_storage"]
    if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_-]*", storage):
        raise ValueError("Invalid Proxmox storage ID")
    if not options["efidisk0"].startswith("@EFI_VOLUME@,"):
        raise ValueError("Staging requires an EFI allocation template")
    disk = options["scsi0"].split(",")
    if disk[0] != "@OS_VOLUME@":
        raise ValueError("Staging requires an OS allocation template, not an existing volume")
    sizes = [part.removeprefix("size=") for part in disk[1:] if part.startswith("size=")]
    if len(sizes) != 1 or not re.fullmatch(r"[1-9][0-9]*G", sizes[0]):
        raise ValueError("OS disk requires one positive size in GiB")
    size = sizes[0]
    disk_options = [part for part in disk[1:] if not part.startswith("size=")] + ["format=qcow2"]
    create = ["qm", "create", str(vmid)]
    for key, value in options.items():
        if key in CREATE_OPTIONS:
            create += [f"--{key}", "0" if key == "onboot" else value]
    efi = options["efidisk0"].replace("@EFI_VOLUME@", f"{storage}:0") + ",format=qcow2"
    commands = [create, ["qm", "set", str(vmid), "--efidisk0", efi]]
    if "image" in guest:
        if disk_image is None or not Path(disk_image).is_absolute() or not disk_image.endswith(".qcow2") or any(c in disk_image for c in ",\n\r"):
            raise ValueError("HAOS requires an absolute decompressed .qcow2 path without commas/newlines")
        commands += [
            ["qm", "set", str(vmid), "--scsi0", ",".join([f"{storage}:0", f"import-from={disk_image}", *disk_options])],
            ["qm", "disk", "resize", str(vmid), "scsi0", size],
            ["qm", "set", str(vmid), "--boot", options["boot"]],
        ]
    else:
        iso = host["hypervisor"]["linux_installer"]["iso_name"]
        if not isinstance(iso, str) or not re.fullmatch(r"[a-zA-Z0-9_.-]+\.iso", iso):
            raise ValueError("A pinned Debian installer filename is required")
        if disk_image is not None:
            raise ValueError("A disk image is only supported for HAOS")
        commands += [
            ["qm", "set", str(vmid), "--scsi0", ",".join([f"{storage}:{size[:-1]}", *disk_options])],
            ["qm", "set", str(vmid), "--ide2", f"{storage}:iso/{iso},media=cdrom"],
            ["qm", "set", str(vmid), "--boot", "order=ide2;scsi0"],
        ]
    return "\n".join(shlex.join(command) for command in commands)


def main():
    parser = argparse.ArgumentParser(description="Print one-time staging commands from a VM allocation template.")
    parser.add_argument("vmid", choices=["100", "101", "102", "199"])
    parser.add_argument("--host", type=Path, default=Path(__file__).with_name("host.json"))
    parser.add_argument("--disk-image", help="Verified decompressed HAOS image path on the Proxmox host")
    args = parser.parse_args()
    try:
        print(render_vm(args.host, args.vmid, args.disk_image))
    except (ValueError, OSError, KeyError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
