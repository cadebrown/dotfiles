const initialState = () => ({
  tick: 14,
  confidence: 82,
  reserve: 72,
  focus: 'stability',
  work: [
    {id: 1, title: 'Sensor calibration', lane: 'validate', effort: 2},
    {id: 2, title: 'Thermal model', lane: 'research', effort: 5}
  ],
  nextId: 3,
  event: 'System initialized. Awaiting next action.'
});

const storageKey = 'webmcp-mission-control-state-v1';
const focusDetails = {
  stability: {label: 'Stability', note: 'Protect the baseline', trajectory: 'stable'},
  latency: {label: 'Latency', note: 'Accelerate research feedback', trajectory: 'accelerating'},
  coverage: {label: 'Coverage', note: 'Expand active experiments', trajectory: 'expanding'}
};
const lanes = new Set(['research', 'build', 'validate']);
const focuses = new Set(Object.keys(focusDetails));
const elements = Object.fromEntries(['tick', 'confidence', 'reserve', 'focus', 'focus-note', 'confidence-note', 'trajectory-chip', 'event-log', 'work-list', 'work-count', 'webmcp-status'].map(id => [id, document.getElementById(id)]));

function loadState() {
  try {
    const candidate = JSON.parse(localStorage.getItem(storageKey));
    if (!candidate || !Number.isInteger(candidate.tick) || !Number.isInteger(candidate.confidence) || !Number.isInteger(candidate.reserve) || !focuses.has(candidate.focus) || !Array.isArray(candidate.work) || !Number.isInteger(candidate.nextId) || typeof candidate.event !== 'string') return initialState();
    if (candidate.work.some(item => !Number.isInteger(item.id) || typeof item.title !== 'string' || !lanes.has(item.lane) || !Number.isInteger(item.effort))) return initialState();
    return candidate;
  } catch {
    return initialState();
  }
}

let state = loadState();

function snapshot() {
  return structuredClone({tick: state.tick, confidence: state.confidence, reserve: state.reserve, focus: state.focus, work: state.work, event: state.event});
}

function persist() {
  try {
    localStorage.setItem(storageKey, JSON.stringify(state));
  } catch {
    // Local persistence is an enhancement; the active page still works without it.
  }
}

function validationError(code, message) {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function requireObject(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) validationError('invalid_input', 'Input must be an object.');
}

const actions = {
  dashboard() {
    return snapshot();
  },
  setFocus(input) {
    requireObject(input);
    if (!focuses.has(input.focus)) validationError('invalid_focus', 'focus must be stability, latency, or coverage.');
    state.focus = input.focus;
    state.event = `Focus changed to ${focusDetails[input.focus].label}.`;
    render();
    return snapshot();
  },
  advance(input = {}) {
    requireObject(input);
    const steps = input.steps ?? 1;
    if (!Number.isInteger(steps) || steps < 1 || steps > 12) validationError('invalid_steps', 'steps must be an integer from 1 through 12.');
    const modifier = state.focus === 'stability' ? 2 : state.focus === 'latency' ? 4 : 3;
    state.tick += steps;
    state.reserve = Math.max(0, state.reserve - steps * 2);
    state.confidence = Math.max(44, Math.min(99, state.confidence + modifier - steps));
    state.event = `Advanced ${steps} tick${steps === 1 ? '' : 's'} with ${focusDetails[state.focus].label.toLowerCase()} focus.`;
    render();
    return snapshot();
  },
  queueWork(input) {
    requireObject(input);
    const title = typeof input.title === 'string' ? input.title.trim().replace(/\s+/g, ' ') : '';
    if (title.length < 3 || title.length > 48) validationError('invalid_title', 'title must be 3 to 48 characters.');
    if (!lanes.has(input.lane)) validationError('invalid_lane', 'lane must be research, build, or validate.');
    if (!Number.isInteger(input.effort) || input.effort < 1 || input.effort > 8) validationError('invalid_effort', 'effort must be an integer from 1 through 8.');
    const item = {id: state.nextId++, title, lane: input.lane, effort: input.effort};
    state.work = [...state.work, item];
    state.event = `Queued ${title} in ${input.lane}.`;
    render();
    return {item, state: snapshot()};
  },
  reset() {
    state = initialState();
    state.event = 'Simulation reset to the baseline scenario.';
    render();
    return snapshot();
  }
};

function render() {
  const detail = focusDetails[state.focus];
  elements.tick.textContent = String(state.tick).padStart(3, '0');
  elements.confidence.textContent = `${state.confidence}%`;
  elements.reserve.textContent = String(state.reserve);
  elements.focus.textContent = detail.label;
  elements['focus-note'].textContent = detail.note;
  elements['confidence-note'].textContent = state.confidence > 74 ? 'Nominal' : 'Watch closely';
  elements['trajectory-chip'].textContent = detail.trajectory;
  elements['event-log'].textContent = state.event;
  elements['work-count'].textContent = `${state.work.length} active`;
  elements['work-list'].replaceChildren(...state.work.map(item => {
    const row = document.createElement('li');
    row.innerHTML = `<strong>${escapeHtml(item.title)}</strong><span class="lane">${escapeHtml(item.lane)}</span><span>${item.effort} units</span>`;
    return row;
  }));
  document.querySelectorAll('[data-focus]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.focus === state.focus)));
  persist();
}

function escapeHtml(value) {
  return value.replace(/[&<>'"]/g, character => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'}[character]));
}

function result(action, payload) {
  return {ok: true, action, message: `${action} completed.`, ...payload};
}

function invoke(action, handler) {
  return async input => {
    try {
      return result(action, {state: handler(input)});
    } catch (error) {
      return {ok: false, action, error: {code: error.code || 'action_failed', message: error.message || 'Action failed.'}, state: snapshot()};
    }
  };
}

const toolDefinitions = [
  {name: 'mission_get_dashboard', description: 'Read the current local simulation state and active work queue.', inputSchema: {type: 'object', properties: {}, additionalProperties: false}, annotations: {readOnlyHint: true}, execute: invoke('mission_get_dashboard', actions.dashboard)},
  {name: 'mission_set_focus', description: 'Set the local simulation focus to stability, latency, or coverage.', inputSchema: {type: 'object', properties: {focus: {type: 'string', enum: [...focuses]}}, required: ['focus'], additionalProperties: false}, annotations: {readOnlyHint: false}, execute: invoke('mission_set_focus', actions.setFocus)},
  {name: 'mission_advance', description: 'Advance the local simulation by a bounded number of ticks.', inputSchema: {type: 'object', properties: {steps: {type: 'integer', minimum: 1, maximum: 12, description: 'Simulation ticks to advance.'}}, additionalProperties: false}, annotations: {readOnlyHint: false}, execute: invoke('mission_advance', actions.advance)},
  {name: 'mission_queue_experiment', description: 'Add a bounded local experiment to the dashboard work queue.', inputSchema: {type: 'object', properties: {title: {type: 'string', minLength: 3, maxLength: 48}, lane: {type: 'string', enum: [...lanes]}, effort: {type: 'integer', minimum: 1, maximum: 8}}, required: ['title', 'lane', 'effort'], additionalProperties: false}, annotations: {readOnlyHint: false}, execute: invoke('mission_queue_experiment', actions.queueWork)},
  {name: 'mission_reset', description: 'Reset this local page simulation to its baseline scenario.', inputSchema: {type: 'object', properties: {}, additionalProperties: false}, annotations: {readOnlyHint: false}, execute: invoke('mission_reset', actions.reset)},
  {name: 'mission_export_state', description: 'Read an editable JSON-compatible export of the current local simulation state.', inputSchema: {type: 'object', properties: {}, additionalProperties: false}, annotations: {readOnlyHint: true}, execute: invoke('mission_export_state', actions.dashboard)}
];

async function registerWebMCPTools() {
  const modelContext = document.modelContext;
  if (!modelContext || typeof modelContext.registerTool !== 'function') {
    elements['webmcp-status'].textContent = 'Page tools unavailable · UI remains active';
    elements['webmcp-status'].classList.add('unavailable');
    return;
  }
  const controller = new AbortController();
  try {
    await Promise.all(toolDefinitions.map(tool => modelContext.registerTool(tool, {signal: controller.signal})));
    elements['webmcp-status'].textContent = `${toolDefinitions.length} page tools ready`;
    elements['webmcp-status'].classList.add('ready');
    window.addEventListener('pagehide', event => {
      if (!event.persisted) controller.abort();
    });
  } catch (error) {
    controller.abort();
    elements['webmcp-status'].textContent = `Page tools unavailable · ${error.name || 'registration failed'}`;
    elements['webmcp-status'].classList.add('unavailable');
  }
}

document.getElementById('advance-button').addEventListener('click', () => actions.advance({steps: 1}));
document.getElementById('reset-button').addEventListener('click', () => actions.reset());
document.getElementById('export-button').addEventListener('click', () => {
  const blob = new Blob([JSON.stringify(snapshot(), null, 2)], {type: 'application/json'});
  const link = Object.assign(document.createElement('a'), {href: URL.createObjectURL(blob), download: 'mission-control-state.json'});
  link.click();
  URL.revokeObjectURL(link.href);
  state.event = 'Exported editable local state as JSON.';
  render();
});
document.querySelectorAll('[data-focus]').forEach(button => button.addEventListener('click', () => actions.setFocus({focus: button.dataset.focus})));
document.getElementById('work-form').addEventListener('submit', event => {
  event.preventDefault();
  const data = new FormData(event.currentTarget);
  try {
    actions.queueWork({title: data.get('title'), lane: data.get('lane'), effort: Number(data.get('effort'))});
    event.currentTarget.reset();
    document.getElementById('work-effort').value = '3';
  } catch (error) {
    state.event = error.message;
    render();
  }
});

render();
void registerWebMCPTools();
