import {defineConfig, devices} from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  reporter: [['list'], ['json', {outputFile: 'artifacts/results.json'}]],
  outputDir: 'artifacts/test-results',
  use: {baseURL: 'http://127.0.0.1:4317', trace: 'retain-on-failure', screenshot: 'only-on-failure'},
  webServer: {command: 'npm start', url: 'http://127.0.0.1:4317', reuseExistingServer: !process.env.CI},
  projects: [
    {name: 'chromium', use: {...devices['Desktop Chrome']}},
    {name: 'firefox', use: {...devices['Desktop Firefox']}},
    {name: 'webkit', use: {...devices['Desktop Safari']}},
    {name: 'mobile', use: {...devices['iPhone 13']}}
  ]
});
