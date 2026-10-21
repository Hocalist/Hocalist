import type { Metadata } from 'next';
import { PasswordRecoveryForm } from './recovery-form';
export const metadata:Metadata={title:'Reset password | Hocalist Admin',referrer:'no-referrer',robots:{index:false,follow:false}};
export default function ResetPassword(){return <PasswordRecoveryForm/>;}
