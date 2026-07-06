const workflow = require('../../workflows/workflow-1.json');

describe('Workflow 1 JSON structure', () => {
  test('has required top-level fields', () => {
    expect(workflow).toHaveProperty('name');
    expect(workflow).toHaveProperty('nodes');
    expect(workflow).toHaveProperty('connections');
    expect(workflow).toHaveProperty('id');
  });

  test('nodes array is non-empty', () => {
    expect(Array.isArray(workflow.nodes)).toBe(true);
    expect(workflow.nodes.length).toBeGreaterThan(0);
  });

  test('all nodes have required fields', () => {
    workflow.nodes.forEach(node => {
      expect(node).toHaveProperty('id');
      expect(node).toHaveProperty('name');
      expect(node).toHaveProperty('type');
      expect(node).toHaveProperty('position');
    });
  });

  test('connections reference valid node names', () => {
    const nodeNames = workflow.nodes.map(n => n.name);
    Object.keys(workflow.connections).forEach(name => {
      expect(nodeNames).toContain(name);
    });
  });

  test('workflow is marked active', () => {
    expect(workflow.active).toBe(true);
  });

  test('has a webhook node', () => {
    const webhookNode = workflow.nodes.find(n => n.type === 'n8n-nodes-base.webhook');
    expect(webhookNode).toBeDefined();
  });
});
