import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import cloud_oauth


class CloudOAuthSetupTests(unittest.TestCase):
    def settings(self):
        return {
            "CONFIGURATION": "Release",
            "ORGENDA_ONEDRIVE_CLIENT_ID": "12345678-1234-1234-1234-123456789abc",
            "ORGENDA_ONEDRIVE_REDIRECT_URI": "orgenda-onedrive://oauth",
            "ORGENDA_GOOGLE_CLIENT_ID": "123456-test.apps.googleusercontent.com",
            "ORGENDA_GOOGLE_URL_SCHEME": "com.googleusercontent.apps.123456-test",
            "ORGENDA_GOOGLE_REDIRECT_URI": "com.googleusercontent.apps.123456-test:/oauth2redirect",
            "ORGENDA_DROPBOX_CLIENT_ID": "testappkey123",
            "ORGENDA_DROPBOX_REDIRECT_URI": "orgenda-dropbox://oauth",
        }

    def validate(self, values):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            result = cloud_oauth.validate_build(values)
        return result, output.getvalue()

    def test_release_requires_all_providers_but_debug_can_build(self):
        for provider, key, _ in cloud_oauth.PROVIDERS:
            settings = self.settings()
            settings[key] = ""
            result, output = self.validate(settings)
            self.assertEqual(result, 1)
            self.assertIn(f"error: Cloud sign-in: {provider}", output)
            settings["CONFIGURATION"] = "Debug"
            result, output = self.validate(settings)
            self.assertEqual(result, 0)
            self.assertIn("warning:", output)

    def test_complete_configuration_passes_and_mismatched_callbacks_fail(self):
        self.assertEqual(self.validate(self.settings()), (0, ""))
        for key in ["ORGENDA_GOOGLE_URL_SCHEME", "ORGENDA_GOOGLE_REDIRECT_URI",
                    "ORGENDA_ONEDRIVE_REDIRECT_URI", "ORGENDA_DROPBOX_REDIRECT_URI"]:
            settings = self.settings()
            settings[key] = "incorrect"
            self.assertEqual(self.validate(settings)[0], 1)

    def test_setup_preserves_existing_ids_derives_google_scheme_and_rejects_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "CloudOAuth.local.xcconfig"
            command = [sys.executable, str(Path(cloud_oauth.__file__)), "configure", "--output", str(path)]
            subprocess.run(command + ["--google", self.settings()["ORGENDA_GOOGLE_CLIENT_ID"]], check=True, capture_output=True)
            subprocess.run(command + ["--dropbox", "testappkey123"], check=True, capture_output=True)
            before = path.read_text()
            self.assertIn("ORGENDA_GOOGLE_URL_SCHEME = com.googleusercontent.apps.123456-test", before)
            self.assertIn("ORGENDA_DROPBOX_CLIENT_ID = testappkey123", before)
            bad = subprocess.run(command + ["--dropbox", "key\nINJECTED_SETTING = YES"], capture_output=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertEqual(path.read_text(), before)


if __name__ == "__main__":
    unittest.main()
