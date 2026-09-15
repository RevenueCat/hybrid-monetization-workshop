import contextlib
import importlib.machinery
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('workshop_check', str(Path(__file__).resolve().parents[1] / 'workshop-check'))
spec = importlib.util.spec_from_loader(loader.name, loader)
check = importlib.util.module_from_spec(spec)
loader.exec_module(check)


class PreflightTests(unittest.TestCase):
    def devices(self, count=1):
        return {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [
            {'name': 'Workshop phone', 'udid': str(i), 'state': 'Booted', 'isAvailable': True,
             'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-16'} for i in range(count)]}}

    def test_custom_named_simulator_and_ambiguity(self):
        self.assertEqual(check.choose_simulator(self.devices(), None)['udid'], '0')
        with self.assertRaises(check.CheckError):
            check.choose_simulator(self.devices(2), None)
        self.assertEqual(check.choose_simulator(self.devices(2), '1')['udid'], '1')
        with self.assertRaises(check.CheckError):
            check.choose_simulator(self.devices(2), 'Workshop phone')

    def test_old_and_unavailable_simulators_rejected(self):
        data = self.devices()
        data['devices']['com.apple.CoreSimulator.SimRuntime.iOS-17-0'] = data['devices'].pop('com.apple.CoreSimulator.SimRuntime.iOS-26-5')
        with self.assertRaises(check.CheckError):
            check.choose_simulator(data, None)
        data = self.devices()
        next(iter(data['devices'].values()))[0]['isAvailable'] = False
        with self.assertRaises(check.CheckError):
            check.choose_simulator(data, None)

    def test_simulator_inventory_reports_actionable_failure_without_tool_output(self):
        with patch.object(check, 'run', side_effect=check.CheckError('secret simulator output')):
            with self.assertRaises(check.CheckError) as result:
                check.simulator_inventory()
        self.assertIn('Open Xcode once', str(result.exception))
        self.assertNotIn('secret', str(result.exception))

    def test_simulator_inventory_rejects_invalid_json(self):
        with patch.object(check, 'run', return_value='not-json'):
            with self.assertRaises(check.CheckError) as result:
                check.simulator_inventory()
        self.assertIn('unreadable device list', str(result.exception))

    def test_command_failures_do_not_disclose_tool_output(self):
        result = subprocess.CompletedProcess([], 4, 'secret-stdout', 'secret-stderr')
        with patch.object(check.subprocess, 'run', return_value=result):
            with self.assertRaises(check.CheckError) as error:
                check.run(['rc'])
        self.assertNotIn('secret', str(error.exception))

    def test_missing_command_and_timeout(self):
        for error in [FileNotFoundError(), subprocess.TimeoutExpired('rc', 30, output='secret')]:
            with patch.object(check.subprocess, 'run', side_effect=error):
                with self.assertRaises(check.CheckError) as result:
                    check.run(['rc'])
                self.assertNotIn('secret', str(result.exception))

    def test_pagination_does_not_claim_complete_inventory(self):
        with patch.object(check, 'run', return_value='{"data":{"items":[],"next_page":"more"}}'):
            with self.assertRaises(check.CheckError):
                check.rc_items('products', 'example')

    def test_missing_expectations_fail_without_echoing_identifiers(self):
        with self.assertRaises(check.CheckError) as error:
            check.require_matches([], 'private-product', 'store_identifier')
        self.assertNotIn('private-product', str(error.exception))
        self.assertEqual(check.require_matches([{'lookup_key': 'example'}], 'example', 'lookup_key'), 1)

    def run_revenuecat(self, settings, respond):
        import json
        calls = []

        def fake_run(argv, timeout=30):
            if argv[0] == 'rc':
                calls.append(argv)
                return respond(argv)
            if argv[:2] == ['xcodebuild', '-version']:
                return 'Xcode 26.6'
            if argv[:2] == ['xcode-select', '-p']:
                return '/Applications/Xcode.app/Contents/Developer'
            if argv[0] == 'xcrun':
                return json.dumps(self.devices())
            return ''

        output = io.StringIO()
        with patch.dict(check.os.environ, {}, clear=True), patch.object(check, 'run', side_effect=fake_run), patch.object(check, 'read_settings', return_value=settings), patch.object(check.shutil, 'which', return_value='/usr/local/bin/rc'), patch.object(check.sys, 'argv', ['workshop-check', '--revenuecat']), contextlib.redirect_stdout(output):
            code = check.main()
        return code, output.getvalue(), calls

    def test_no_project_accepts_empty_or_existing_account_inventory(self):
        for response in ['{"data":{"items":[]}}', '{"data":{"items":[{"id":"private-project"}],"next_page":"more"}}']:
            code, output, calls = self.run_revenuecat({}, lambda argv: response)
            self.assertEqual(code, 0)
            self.assertIn('Project not configured; catalog checks skipped', output)
            self.assertNotIn('private-project', output)
            self.assertEqual(calls, [['rc', 'projects', 'list', '--json', '--no-input']])

    def test_no_project_still_requires_authentication(self):
        def denied(argv):
            raise check.CheckError('Command failed (exit 4); authentication unavailable.')
        code, output, calls = self.run_revenuecat({}, denied)
        self.assertEqual(code, 1)
        self.assertNotIn('catalog checks skipped', output)
        self.assertIn('NOT READY', output)

    def test_inaccessible_configured_project_fails_without_fallback(self):
        def denied(argv):
            raise check.CheckError('Command failed (exit 5); project unavailable.')
        code, output, calls = self.run_revenuecat({'REVENUECAT_PROJECT_ID': 'private-project'}, denied)
        self.assertEqual(code, 1)
        self.assertEqual(calls[0][1:5], ['apps', 'list', '--project-id', 'private-project'])
        self.assertNotIn('catalog checks skipped', output)
        self.assertNotIn('private-project', output)

    def test_configured_project_still_checks_catalog(self):
        def catalog(argv):
            return '{"data":{"items":[{"id":"private-app"}]}}' if argv[1] == 'apps' else '{"data":{"items":[]}}'
        code, output, calls = self.run_revenuecat({'REVENUECAT_PROJECT_ID': 'private-project', 'REVENUECAT_TEST_APP_ID': 'private-app', 'REVENUECAT_TEST_API_KEY': 'test_never_display'}, catalog)
        self.assertEqual(code, 0)
        self.assertEqual([call[1] for call in calls], ['apps', 'products', 'entitlements', 'offerings'])
        self.assertNotIn('test_never_display', output)
        self.assertNotIn('private-app', output)

    def test_main_does_not_print_local_settings(self):
        def fake_run(argv, timeout=30):
            if argv[:2] == ['xcodebuild', '-version']:
                return 'Xcode 26.6'
            if argv[:2] == ['xcode-select', '-p']:
                return '/Applications/Xcode.app/Contents/Developer'
            if argv[0] == 'xcrun':
                import json
                return json.dumps(self.devices())
            return ''
        output = io.StringIO()
        with patch.object(check, 'run', side_effect=fake_run), patch.object(check, 'read_settings', return_value={'REVENUECAT_TEST_API_KEY': 'test_never_display'}), patch.object(check.sys, 'argv', ['workshop-check']), contextlib.redirect_stdout(output):
            self.assertEqual(check.main(), 0)
        self.assertNotIn('test_never_display', output.getvalue())
        self.assertIn('SKIP  RevenueCat', output.getvalue())


if __name__ == '__main__':
    unittest.main()
