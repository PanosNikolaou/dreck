# Mermaid diagrams

This folder contains Mermaid diagrams that can be embedded into a TSX view or rendered in a Markdown preview.

Example pattern for a React/TSX component:

```tsx
import Mermaid from './components/Mermaid';

export function DiagramCard() {
  return <Mermaid chart={`flowchart LR\nA-->B`}/>
}
```

If your project uses a Markdown plugin instead, paste the diagram text directly into the markdown file.
