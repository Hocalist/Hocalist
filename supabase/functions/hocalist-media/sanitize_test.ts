import jpeg from 'npm:jpeg-js@0.4.4';
import {sanitizeImage} from './sanitize.ts';
import { Buffer } from 'node:buffer';
Deno.test('JPEG encoding works in an isolate without the Node Buffer global',()=>{
 const runtime=globalThis as typeof globalThis & {Buffer?:typeof Buffer};
 const original=runtime.Buffer;
 const input=jpeg.encode({width:2,height:2,data:new Uint8Array(16).fill(255)},80).data;
 try {
  runtime.Buffer=undefined;
  const result=sanitizeImage(new Uint8Array(input));
  if(result.bytes[0]!==255||result.bytes[1]!==216||result.width!==2)throw Error('invalid output');
 } finally {runtime.Buffer=original;}
});
function assert(v:unknown){if(!v)throw Error('assertion failed');}
Deno.test('real JPEG sanitizer removes private EXIF and comments while preserving pixels',()=>{
 const pixels=new Uint8Array(4*4*4).fill(255);
 const original=jpeg.encode({width:4,height:4,data:pixels,comments:['private location sentinel']} as Parameters<typeof jpeg.encode>[0],80).data;
 const marker=new TextEncoder().encode('Exif\0\0private GPS sentinel');
 const segment=new Uint8Array([255,225,0,marker.length+2,...marker]);
 const input=new Uint8Array([...original.slice(0,2),...segment,...original.slice(2)]);
 const output=sanitizeImage(input);
 assert(output.width===4&&output.height===4);
 assert(!new TextDecoder().decode(output.bytes).includes('sentinel'));
 const decoded=jpeg.decode(output.bytes,{useTArray:true});
 assert(decoded.data[0]>240&&decoded.width===4);
});
Deno.test('malformed image is refused',()=>{
 let rejected=false;try{sanitizeImage(new Uint8Array([255,216,0,1]));}catch{rejected=true;}assert(rejected);
});
