import { useCallback, useState, useRef } from 'react';
import type { Node, Edge, NodeChange, EdgeChange, Connection } from '@xyflow/react';
import {
  ReactFlow,
  useNodesState,
  useEdgesState,
  Controls,
  Background,
  BackgroundVariant,
  MarkerType,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge,
  Handle,
  Position,
  reconnectEdge,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import './App.css';

const nodeWidth = 240;
const nodeHeight = 70;

type Phase = 'setup' | 'executive' | 'planner' | 'worker' | 'decision' | 'done';

const phaseColors: Record<Phase, { bg: string; border: string }> = {
  setup: { bg: '#f0f7ff', border: '#4a90d9' },
  executive: { bg: '#fef3f0', border: '#d94a4a' },
  planner: { bg: '#f5f0ff', border: '#8b5cf6' },
  worker: { bg: '#f0fff4', border: '#38a169' },
  decision: { bg: '#fff8e6', border: '#c9a227' },
  done: { bg: '#e8f5e9', border: '#2e7d32' },
};

const allSteps: { id: string; label: string; description: string; phase: Phase }[] = [
  // Setup phase
  { id: '1', label: 'You define project goals', description: 'High-level objectives in project.json', phase: 'setup' },
  { id: '2', label: 'Run burns.sh', description: 'Starts the swarm orchestrator', phase: 'setup' },
  
  // Executive phase
  { id: '3', label: 'Executive reviews state', description: 'Monitors progress & health', phase: 'executive' },
  { id: '4', label: 'Spawn planners?', description: 'Decides resource allocation', phase: 'decision' },
  
  // Planner phase
  { id: '5', label: 'Planner explores codebase', description: 'Understands the domain', phase: 'planner' },
  { id: '6', label: 'Creates atomic tasks', description: 'Small, completable units', phase: 'planner' },
  
  // Worker phase (parallel)
  { id: '7', label: 'Workers claim tasks', description: 'Lock-free queue operations', phase: 'worker' },
  { id: '8', label: 'Implement in parallel', description: 'Multiple workers concurrently', phase: 'worker' },
  { id: '9', label: 'Commit & push', description: 'Each on own branch', phase: 'worker' },
  { id: '10', label: 'Update task status', description: 'Mark complete or failed', phase: 'worker' },
  
  // Decision
  { id: '11', label: 'More work?', description: '', phase: 'decision' },
  
  // Done
  { id: '12', label: 'Project Complete!', description: 'All goals achieved', phase: 'done' },
];

const notes = [
  {
    id: 'note-1',
    appearsWithStep: 3,
    position: { x: 520, y: 180 },
    color: { bg: '#fef3f0', border: '#d94a4a' },
    content: `Executive Agent:
• Monitors overall progress
• Spawns/terminates planners  
• Makes go/no-go decisions
• Runs periodically, not every cycle`,
  },
  {
    id: 'note-2',
    appearsWithStep: 6,
    position: { x: 520, y: 380 },
    color: { bg: '#f5f0ff', border: '#8b5cf6' },
    content: `Planner Agent:
• Explores assigned area
• Creates small, atomic tasks
• Ensures dependency ordering
• Can spawn sub-planners`,
  },
  {
    id: 'note-3',
    appearsWithStep: 8,
    position: { x: 520, y: 580 },
    color: { bg: '#f0fff4', border: '#38a169' },
    content: `Worker Agents (parallel):
• Focus on ONE task only
• Don't coordinate with each other
• Grind until task is done
• Push to own branch`,
  },
  {
    id: 'note-4',
    appearsWithStep: 11,
    position: { x: 520, y: 780 },
    color: { bg: '#fff8e6', border: '#c9a227' },
    content: `Loop continues until:
• All tasks complete → SUCCESS
• Project stuck → HUMAN NEEDED  
• Max cycles reached → TIMEOUT`,
  },
];

function CustomNode({ data }: { data: { title: string; description: string; phase: Phase } }) {
  const colors = phaseColors[data.phase];
  return (
    <div 
      className="custom-node"
      style={{ 
        backgroundColor: colors.bg, 
        borderColor: colors.border 
      }}
    >
      <Handle type="target" position={Position.Top} id="top" />
      <Handle type="target" position={Position.Left} id="left" />
      <Handle type="source" position={Position.Right} id="right" />
      <Handle type="source" position={Position.Bottom} id="bottom" />
      <Handle type="target" position={Position.Right} id="right-target" style={{ right: 0 }} />
      <Handle type="target" position={Position.Bottom} id="bottom-target" style={{ bottom: 0 }} />
      <Handle type="source" position={Position.Top} id="top-source" />
      <Handle type="source" position={Position.Left} id="left-source" />
      <div className="node-content">
        <div className="node-title">{data.title}</div>
        {data.description && <div className="node-description">{data.description}</div>}
      </div>
    </div>
  );
}

function NoteNode({ data }: { data: { content: string; color: { bg: string; border: string } } }) {
  return (
    <div 
      className="note-node"
      style={{
        backgroundColor: data.color.bg,
        borderColor: data.color.border,
      }}
    >
      <pre>{data.content}</pre>
    </div>
  );
}

const nodeTypes = { custom: CustomNode, note: NoteNode };

// Vertical layout with parallel worker section
const positions: { [key: string]: { x: number; y: number } } = {
  // Setup (top)
  '1': { x: 200, y: 20 },
  '2': { x: 200, y: 110 },
  
  // Executive
  '3': { x: 200, y: 200 },
  '4': { x: 200, y: 290 },
  
  // Planner
  '5': { x: 200, y: 380 },
  '6': { x: 200, y: 470 },
  
  // Workers (show parallel nature)
  '7': { x: 200, y: 560 },
  '8': { x: 200, y: 650 },
  '9': { x: 200, y: 740 },
  '10': { x: 200, y: 830 },
  
  // Decision & Done
  '11': { x: 200, y: 920 },
  '12': { x: 200, y: 1010 },
  
  // Notes
  ...Object.fromEntries(notes.map(n => [n.id, n.position])),
};

const edgeConnections: { source: string; target: string; sourceHandle?: string; targetHandle?: string; label?: string }[] = [
  // Setup flow
  { source: '1', target: '2', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '2', target: '3', sourceHandle: 'bottom', targetHandle: 'top' },
  
  // Executive flow
  { source: '3', target: '4', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '4', target: '5', sourceHandle: 'bottom', targetHandle: 'top', label: 'Yes' },
  
  // Planner flow
  { source: '5', target: '6', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '6', target: '7', sourceHandle: 'bottom', targetHandle: 'top' },
  
  // Worker flow
  { source: '7', target: '8', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '8', target: '9', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '9', target: '10', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '10', target: '11', sourceHandle: 'bottom', targetHandle: 'top' },
  
  // Loop back
  { source: '11', target: '3', sourceHandle: 'left-source', targetHandle: 'left', label: 'Yes' },
  
  // Exit
  { source: '11', target: '12', sourceHandle: 'bottom', targetHandle: 'top', label: 'No' },
];

function createNode(step: typeof allSteps[0], visible: boolean, position?: { x: number; y: number }): Node {
  return {
    id: step.id,
    type: 'custom',
    position: position || positions[step.id],
    data: {
      title: step.label,
      description: step.description,
      phase: step.phase,
    },
    style: {
      width: nodeWidth,
      height: nodeHeight,
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
      pointerEvents: visible ? 'auto' : 'none',
    },
  };
}

function createEdge(conn: typeof edgeConnections[0], visible: boolean): Edge {
  return {
    id: `e${conn.source}-${conn.target}`,
    source: conn.source,
    target: conn.target,
    sourceHandle: conn.sourceHandle,
    targetHandle: conn.targetHandle,
    label: visible ? conn.label : undefined,
    animated: visible,
    style: {
      stroke: '#222',
      strokeWidth: 2,
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
    },
    labelStyle: {
      fill: '#222',
      fontWeight: 600,
      fontSize: 14,
    },
    labelShowBg: true,
    labelBgPadding: [8, 4] as [number, number],
    labelBgStyle: {
      fill: '#fff',
      stroke: '#222',
      strokeWidth: 1,
    },
    markerEnd: {
      type: MarkerType.ArrowClosed,
      color: '#222',
    },
  };
}

function createNoteNode(note: typeof notes[0], visible: boolean, position?: { x: number; y: number }): Node {
  return {
    id: note.id,
    type: 'note',
    position: position || positions[note.id],
    data: { content: note.content, color: note.color },
    style: {
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
      pointerEvents: visible ? 'auto' : 'none',
    },
    draggable: true,
    selectable: false,
    connectable: false,
  };
}

function App() {
  const [visibleCount, setVisibleCount] = useState(1);
  const nodePositions = useRef<{ [key: string]: { x: number; y: number } }>({ ...positions });

  const getNodes = (count: number) => {
    const stepNodes = allSteps.map((step, index) =>
      createNode(step, index < count, nodePositions.current[step.id])
    );
    const noteNodes = notes.map(note => {
      const noteVisible = count >= note.appearsWithStep;
      return createNoteNode(note, noteVisible, nodePositions.current[note.id]);
    });
    return [...stepNodes, ...noteNodes];
  };

  const initialNodes = getNodes(1);
  const initialEdges = edgeConnections.map((conn, index) =>
    createEdge(conn, index < 0)
  );

  const [nodes, setNodes] = useNodesState(initialNodes);
  const [edges, setEdges] = useEdgesState(initialEdges);

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      changes.forEach((change) => {
        if (change.type === 'position' && change.position) {
          nodePositions.current[change.id] = change.position;
        }
      });
      setNodes((nds) => applyNodeChanges(changes, nds));
    },
    [setNodes]
  );

  const onEdgesChange = useCallback(
    (changes: EdgeChange[]) => {
      setEdges((eds) => applyEdgeChanges(changes, eds));
    },
    [setEdges]
  );

  const onConnect = useCallback(
    (connection: Connection) => {
      setEdges((eds) => addEdge({ ...connection, animated: true, style: { stroke: '#222', strokeWidth: 2 }, markerEnd: { type: MarkerType.ArrowClosed, color: '#222' } }, eds));
    },
    [setEdges]
  );

  const onReconnect = useCallback(
    (oldEdge: Edge, newConnection: Connection) => {
      setEdges((eds) => reconnectEdge(oldEdge, newConnection, eds));
    },
    [setEdges]
  );

  const getEdgeVisibility = (conn: typeof edgeConnections[0], visibleStepCount: number) => {
    const sourceIndex = allSteps.findIndex(s => s.id === conn.source);
    const targetIndex = allSteps.findIndex(s => s.id === conn.target);
    return sourceIndex < visibleStepCount && targetIndex < visibleStepCount;
  };

  const handleNext = useCallback(() => {
    if (visibleCount < allSteps.length) {
      const newCount = visibleCount + 1;
      setVisibleCount(newCount);

      setNodes(getNodes(newCount));
      setEdges(
        edgeConnections.map((conn) =>
          createEdge(conn, getEdgeVisibility(conn, newCount))
        )
      );
    }
  }, [visibleCount, setNodes, setEdges]);

  const handlePrev = useCallback(() => {
    if (visibleCount > 1) {
      const newCount = visibleCount - 1;
      setVisibleCount(newCount);

      setNodes(getNodes(newCount));
      setEdges(
        edgeConnections.map((conn) =>
          createEdge(conn, getEdgeVisibility(conn, newCount))
        )
      );
    }
  }, [visibleCount, setNodes, setEdges]);

  const handleReset = useCallback(() => {
    setVisibleCount(1);
    nodePositions.current = { ...positions };
    setNodes(getNodes(1));
    setEdges(edgeConnections.map((conn, index) => createEdge(conn, index < 0)));
  }, [setNodes, setEdges]);

  return (
    <div className="app-container">
      <div className="header">
        <h1>How Mr. Burns Works</h1>
        <p>Executive-Planner-Worker autonomous agent swarm</p>
      </div>
      <div className="flow-container">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onReconnect={onReconnect}
          fitView
          fitViewOptions={{ padding: 0.2 }}
          nodesDraggable={true}
          nodesConnectable={true}
          edgesReconnectable={true}
          elementsSelectable={true}
          deleteKeyCode={['Backspace', 'Delete']}
          panOnDrag={true}
          panOnScroll={true}
          zoomOnScroll={true}
          zoomOnPinch={true}
          zoomOnDoubleClick={true}
          selectNodesOnDrag={false}
        >
          <Background variant={BackgroundVariant.Dots} gap={20} size={1} color="#ddd" />
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
      <div className="controls">
        <button onClick={handlePrev} disabled={visibleCount <= 1}>
          Previous
        </button>
        <span className="step-counter">
          Step {visibleCount} of {allSteps.length}
        </span>
        <button onClick={handleNext} disabled={visibleCount >= allSteps.length}>
          Next
        </button>
        <button onClick={handleReset} className="reset-btn">
          Reset
        </button>
      </div>
      <div className="instructions">
        Click Next to reveal each step of the swarm architecture
      </div>
    </div>
  );
}

export default App;
