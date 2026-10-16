import jpeg from 'npm:jpeg-js@0.4.4';
import { Buffer } from 'node:buffer';
export function sanitizeImage(bytes: Uint8Array) {
 // Bundled jpeg-js uses Buffer.from while encoding; Edge isolates need not
 // expose Node globals even though the decoder's typed-array mode works.
 const runtime = globalThis as typeof globalThis & { Buffer?: typeof Buffer };
 if (runtime.Buffer === undefined) runtime.Buffer = Buffer;
 const decoded=jpeg.decode(bytes,{useTArray:true,tolerantDecoding:false,maxResolutionInMP:4,maxMemoryUsageInMB:64});
 if(decoded.width>2048||decoded.height>2048)throw Error('dimensions');
 // Re-encode pixels only; never forward EXIF, GPS, or comments.
 const encoded=jpeg.encode({width:decoded.width,height:decoded.height,data:decoded.data},80);
 return {bytes:new Uint8Array(encoded.data),width:decoded.width,height:decoded.height};
}
