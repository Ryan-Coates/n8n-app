const fs = require('fs');
const path = require('path');

describe('Deployment readiness checks', () => {
  test('docker-compose.yml exists', () => {
    const p = path.join(__dirname, '../../docker-compose.yml');
    expect(fs.existsSync(p)).toBe(true);
  });

  test('.env.example exists', () => {
    const p = path.join(__dirname, '../../.env.example');
    expect(fs.existsSync(p)).toBe(true);
  });

  test('all workflow JSON files are valid JSON', () => {
    const workflowDir = path.join(__dirname, '../../workflows');
    const files = fs.readdirSync(workflowDir).filter(f => f.endsWith('.json'));
    expect(files.length).toBeGreaterThan(0);
    files.forEach(file => {
      const content = fs.readFileSync(path.join(workflowDir, file), 'utf8');
      expect(() => JSON.parse(content)).not.toThrow();
    });
  });

  test('all workflow files have name and nodes fields', () => {
    const workflowDir = path.join(__dirname, '../../workflows');
    const files = fs.readdirSync(workflowDir).filter(f => f.endsWith('.json'));
    files.forEach(file => {
      const wf = JSON.parse(fs.readFileSync(path.join(workflowDir, file), 'utf8'));
      expect(wf).toHaveProperty('name');
      expect(wf).toHaveProperty('nodes');
    });
  });

  test('polling-service deploy script exists and is non-empty', () => {
    const p = path.join(__dirname, '../../polling-service/deploy-manager.sh');
    expect(fs.existsSync(p)).toBe(true);
    const content = fs.readFileSync(p, 'utf8');
    expect(content.length).toBeGreaterThan(100);
  });

  test('polling-service Dockerfile exists', () => {
    const p = path.join(__dirname, '../../polling-service/Dockerfile');
    expect(fs.existsSync(p)).toBe(true);
  });
});
