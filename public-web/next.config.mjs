/** @type {import('next').NextConfig} */
const nextConfig = {
  poweredByHeader: false,
  async redirects() {
    // The app's signed-in billing handoff uses www. Keep checkout returns on
    // that same host so its private session and Return to app cookies survive.
    return [{source:'/billing/:path*',has:[{type:'host',value:'hocalist.com'}],
      destination:'https://www.hocalist.com/billing/:path*',permanent:false}];
  },
  async headers() {
    const rules = [{ source: '/:path*', headers: [
      { key: 'Content-Security-Policy', value: "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; script-src 'self' 'unsafe-inline'" + (process.env.NODE_ENV === 'production' ? '' : " 'unsafe-eval'") + "; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob: https://www.hocalist.com https://hocalist.com https://images.pexels.com; connect-src 'self'" },
      { key: 'X-Frame-Options', value: 'DENY' },
      { key: 'X-Content-Type-Options', value: 'nosniff' },
      { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
      { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
    ] }];
    if (process.env.HOCALIST_PAYGO_TEST_ENABLED === 'true') {
      const base = rules[0].headers[0].value;
      rules.push({ source: '/billing/:path*', headers: [{ key: 'Content-Security-Policy', value: base
        .replace("script-src 'self'", "script-src 'self' https://js.stripe.com https://*.js.stripe.com")
        .replace("connect-src 'self'", "connect-src 'self' https://api.stripe.com")
        + '; frame-src https://js.stripe.com https://*.js.stripe.com https://hooks.stripe.com' }] });
    }
    return rules;
  },
};
export default nextConfig;
