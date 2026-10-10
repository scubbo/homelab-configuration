import importlib.util
import json
from pathlib import Path
import shlex
import tempfile
import unittest


BASE = Path(__file__).resolve().parent


class RenderVMTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("render_vm", BASE / "render_vm.py")
        cls.renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.renderer)

    def render(self, vmid, disk_image=None, host_path=BASE / "host.json"):
        return [shlex.split(line) for line in self.renderer.render_vm(host_path, vmid, disk_image).splitlines()]

    def options(self, command):
        return dict(zip(command[3::2], command[4::2]))

    def test_debian_guests_allocate_manifest_disks_and_use_pinned_installer(self):
        host = json.loads((BASE / "host.json").read_text())
        for vmid, name, cores, memory, size in [
            ("101", "eps-base", "8", "16384", "128"),
            ("102", "eps-gpu", "8", "16384", "64"),
            ("199", "network-probe", "1", "1024", "16"),
        ]:
            with self.subTest(vmid=vmid):
                commands = self.render(vmid)
                create = self.options(commands[0])
                self.assertEqual(commands[0][:3], ["qm", "create", vmid])
                self.assertEqual((create["--name"], create["--cores"], create["--memory"]), (name, cores, memory))
                self.assertEqual(create["--onboot"], "0")
                self.assertIn(["qm", "set", vmid, "--scsi0", f"vm-local:{size},backup=1,cache=none,discard=on,iothread=1,format=qcow2"], commands)
                self.assertIn(["qm", "set", vmid, "--ide2", f"vm-local:iso/{host['hypervisor']['linux_installer']['iso_name']},media=cdrom"], commands)
                self.assertEqual(commands[-1], ["qm", "set", vmid, "--boot", "order=ide2;scsi0"])
                self.assertFalse(any("--hostpci0" in c or "start" in c or "--usb0" in c for c in commands))

    def test_haos_import_quotes_image_path_and_enlarges_without_iso(self):
        image = "/root/image files/haos;touch unused.qcow2"
        commands = self.render("100", image)
        self.assertIn(["qm", "set", "100", "--scsi0", f"vm-local:0,import-from={image},backup=1,cache=none,discard=on,iothread=1,format=qcow2"], commands)
        self.assertIn(["qm", "disk", "resize", "100", "scsi0", "64G"], commands)
        self.assertEqual(commands[-1], ["qm", "set", "100", "--boot", "order=scsi0"])
        self.assertFalse(any("--ide2" in c or "--usb0" in c for c in commands))

    def test_haos_requires_absolute_uncompressed_image_path(self):
        for image in [None, "haos.qcow2", "/root/haos.qcow2.xz", "/root/haos,extra.qcow2"]:
            with self.subTest(image=image), self.assertRaises(ValueError):
                self.render("100", image)

    def test_manifest_edits_drive_output_and_invalid_options_are_rejected(self):
        host = json.loads((BASE / "host.json").read_text())
        text = (BASE / host["guests"]["101"]["manifest"]).read_text()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            host["guests"]["101"]["manifest"] = "guest.conf.in"
            (path / "host.json").write_text(json.dumps(host))
            manifest = path / "guest.conf.in"
            manifest.write_text(text.replace("memory: 16384", "memory: 20480"))
            self.assertEqual(self.options(self.render("101", host_path=path / "host.json")[0])["--memory"], "20480")
            for invalid in [text + "memory: 1024\n", text + "args: -arbitrary\n", text.replace("size=128G", "size=bad"), text.replace("@OS_VOLUME@", "vm-local:101/existing.qcow2")]:
                manifest.write_text(invalid)
                with self.assertRaises(ValueError):
                    self.render("101", host_path=path / "host.json")

    def test_unknown_guest_and_unconfigured_installer_fail(self):
        with self.assertRaises(ValueError):
            self.render("999")
        host = json.loads((BASE / "host.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            host["guests"]["101"]["manifest"] = str(BASE / host["guests"]["101"]["manifest"])
            host["hypervisor"]["linux_installer"]["iso_name"] = None
            (path / "host.json").write_text(json.dumps(host))
            with self.assertRaises(ValueError):
                self.render("101", host_path=path / "host.json")


if __name__ == "__main__":
    unittest.main()
