"""Offline validation only: no network requests and no real credentials."""
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('dbcheck', ROOT/'tools/check_dev_database.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class DatabaseProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = pathlib.Path(self.temp.name)/'client.cnf'
        self.base = '[client]\nhost=example.invalid\nport=3306\nuser=fixture\npassword=fixture\n'
        self.save(self.base)

    def save(self, text):
        self.path.write_text(text,encoding='utf-8')
        self.path.chmod(0o600)

    def test_development_names_only(self):
        for name in ('us1_dev','s123_us1_dev'):
            self.assertEqual(probe.validate_config(self.path,name),self.path.resolve())
        for name in ('us1_prod','mysql','us1_dev;DROP DATABASE x','development'):
            with self.assertRaises(ValueError): probe.validate_config(self.path,name)

    def test_forbidden_client_options(self):
        self.save(self.base+'init-command=DELETE FROM example\n')
        with self.assertRaises(ValueError): probe.validate_config(self.path,'us1_dev')

    def test_placeholders_refused(self):
        self.save(self.base.replace('example.invalid','REPLACE_HOST'))
        with self.assertRaises(ValueError): probe.validate_config(self.path,'us1_dev')

    def test_git_tree_refused(self):
        (self.path.parent/'.git').mkdir()
        with self.assertRaises(ValueError): probe.validate_config(self.path,'us1_dev')

    def test_command_has_no_password_and_requires_tls(self):
        args = probe.build_command('mariadb',self.path,'us1_dev')
        self.assertTrue(args[1].startswith('--defaults-file='))
        self.assertFalse(any('password' in item for item in args))
        self.assertIn('--ssl-verify-server-cert',args)
        self.assertIn('--local-infile=0',args)
        self.assertNotRegex(probe.SQL.upper(),r'\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b')

    def test_expected_response(self):
        result=probe.parse_result('s123_us1_dev\t1\n0\nSsl_cipher\tTLS_FAKE\n','s123_us1_dev')
        self.assertEqual(result['table_count'],0)
        self.assertFalse(result['writes_performed'])

    def test_unencrypted_or_wrong_database_refused(self):
        for response in ('us1_dev\t1\n0\nSsl_cipher\t\n','us1_prod\t1\n0\nSsl_cipher\tTLS_FAKE\n'):
            with self.assertRaises(ValueError): probe.parse_result(response,'us1_dev')
