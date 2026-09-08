import {defineConfig} from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  reporter: 'list',
  use: {baseURL: 'http://127.0.0.1:4318', trace: 'retain-on-failure', screenshot: 'only-on-failure'},
  webServer: {command: 'npm start', url: 'http://127.0.0.1:4318', reuseExistingServer: !process.env.CI}
});
