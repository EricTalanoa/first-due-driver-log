import { useEffect, useRef, type ReactNode } from 'react';
import { X } from 'lucide-react';

export function Modal({ title, children, onClose, wide }: { title: string; children: ReactNode; onClose: () => void; wide?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { ref.current?.showModal(); }, []);
  return <dialog ref={ref} className={wide ? 'wide' : undefined} onCancel={e => { e.preventDefault(); onClose(); }}><div className="modal-head"><h2>{title}</h2><button className="icon" aria-label="Close" onClick={onClose}><X size={22} /></button></div>{children}</dialog>;
}
export function Field({ label, children }: { label: string; children: ReactNode }) { return <label className="field"><span>{label}</span>{children}</label>; }
