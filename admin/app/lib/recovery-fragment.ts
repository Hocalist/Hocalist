export function recoveryFragment(hash:string):{token:string;error:boolean} {
 const params=new URLSearchParams(hash.replace(/^#/,''));
 const token=params.get('access_token')??'';
 return {token:params.get('type')==='recovery'&&!params.has('error')&&token.length<=8000?token:'',error:params.has('error')||Boolean(hash)&&(!token||params.get('type')!=='recovery')};
}
