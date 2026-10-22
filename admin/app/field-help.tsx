import type {ReactNode} from 'react';
export function FieldHelp({label,children}:{label:string;children:ReactNode}){return <details className="field-help"><summary aria-label={`Explain ${label}`}><span aria-hidden="true">i</span></summary><div>{children}</div></details>}
