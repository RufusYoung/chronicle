import http from 'node:http';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import express from 'express';
import {rateLimit} from 'express-rate-limit';
import {authorizationHandler} from '@modelcontextprotocol/sdk/server/auth/handlers/authorize.js';
import {tokenHandler} from '@modelcontextprotocol/sdk/server/auth/handlers/token.js';
import {clientRegistrationHandler} from '@modelcontextprotocol/sdk/server/auth/handlers/register.js';
import {revocationHandler} from '@modelcontextprotocol/sdk/server/auth/handlers/revoke.js';
import {requireBearerAuth} from '@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js';
import {StreamableHTTPServerTransport} from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import {PrivateOAuth, SCOPES} from './auth.mjs';
import {Catalog} from './catalog.mjs';
import {createMcp} from './tools.mjs';

export function createGateway(options) {
  const base = options.baseUrl.replace(/\/$/,''), url = new URL(base), prefix = url.pathname;
  if(url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost','127.0.0.1'].includes(url.hostname))) throw new Error('Public MCP requires HTTPS');
  if(!/^\/[a-z0-9-]+$/.test(prefix) || url.search || url.hash || url.username || url.password) throw new Error('Invalid base URL');
  if(!/^[a-f0-9]{32}:[a-f0-9]{64}$/.test(options.passwordHash)) throw new Error('Strong password hash required');
  const catalog = new Catalog(options.snapshot);
  const app = express(); app.disable('x-powered-by');
  if(options.trustProxy) app.set('trust proxy',1);
  const server = http.createServer(app);
  server.requestTimeout = 15000; server.headersTimeout = 10000;
  const provider = new PrivateOAuth({...options,baseUrl:base});
  app.use((req,res,next)=>{
    res.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"});
    if(req.headers.host !== url.host) return res.status(403).json({error:'Host not allowed'});
    if(req.headers.origin && ![url.origin,'https://chatgpt.com'].includes(req.headers.origin)) return res.status(403).json({error:'Origin not allowed'});
    next();
  });
  app.get(`${prefix}/health`,(req,res)=>res.json({ok:true,service:'chronicle-private-mcp',version:'1.0.0'}));
  app.get([prefix,`${prefix}/`],(req,res)=>res.type('html').send('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Chronicle MCP</title><h1>Chronicle 私人 MCP</h1><p>只读项目讨论接口。连接 /mcp，认证选择 OAuth 和 DCR。需要私人访问口令。</p></html>'));
  const metadata = {issuer:base,authorization_response_iss_parameter_supported:true,authorization_endpoint:`${base}/authorize`,token_endpoint:`${base}/token`,registration_endpoint:`${base}/register`,revocation_endpoint:`${base}/revoke`,response_types_supported:['code'],grant_types_supported:['authorization_code','refresh_token'],code_challenge_methods_supported:['S256'],token_endpoint_auth_methods_supported:['none','client_secret_post'],scopes_supported:SCOPES};
  app.get([`${prefix}/.well-known/oauth-authorization-server`,`/.well-known/oauth-authorization-server${prefix}`],(req,res)=>res.json(metadata));
  const metadataUrl = `${base}/.well-known/oauth-protected-resource`;
  app.get([`${prefix}/.well-known/oauth-protected-resource`,`/.well-known/oauth-protected-resource${prefix}/mcp`],(req,res)=>res.json({resource:`${base}/mcp`,authorization_servers:[base],scopes_supported:SCOPES,resource_name:'Chronicle Private Project'}));
  const rateOptions = options.disableRateLimits ? false : undefined;
  app.use(`${prefix}/authorize`,(req,res,next)=>{
    const redirect = res.redirect.bind(res);
    // SDK-generated OAuth error redirects also need RFC 9207 issuer identification.
    res.redirect = (status,target)=>{
      if(typeof status === 'string') {target = status; status = 302;}
      const callback = new URL(target); callback.searchParams.set('iss',base);
      return redirect(status,callback.href);
    };
    next();
  },authorizationHandler({provider,rateLimit:rateOptions}));
  app.use(`${prefix}/token`,tokenHandler({provider,rateLimit:rateOptions}));
  app.use(`${prefix}/register`,clientRegistrationHandler({clientsStore:provider.clientsStore,clientSecretExpirySeconds:0,rateLimit:rateOptions}));
  app.use(`${prefix}/revoke`,revocationHandler({provider,rateLimit:rateOptions}));
  const limit = (max,windowMs) => options.disableRateLimits ? (req,res,next)=>next() : rateLimit({windowMs,max,standardHeaders:true,legacyHeaders:false});
  app.post(`${prefix}/login`,limit(15,15*60000),express.urlencoded({extended:false,limit:'4kb'}),(req,res)=>provider.login(req,res));
  app.use(`${prefix}/mcp`,requireBearerAuth({verifier:provider,requiredScopes:SCOPES,resourceMetadataUrl:metadataUrl}),limit(120,60000));
  app.post(`${prefix}/mcp`,express.json({limit:'16kb'}),async(req,res)=>{
    const mcp = createMcp(catalog), transport = new StreamableHTTPServerTransport({sessionIdGenerator:undefined,enableJsonResponse:true});
    res.on('close',()=>{void transport.close(); void mcp.close();});
    try {await mcp.connect(transport); await transport.handleRequest(req,res,req.body);}
    catch {if(!res.headersSent) res.status(500).json({jsonrpc:'2.0',id:null,error:{code:-32603,message:'MCP request failed'}});}
  });
  app.all(`${prefix}/mcp`,(req,res)=>res.status(405).set('Allow','POST').json({error:'Use MCP Streamable HTTP POST'}));
  app.use((err,req,res,next)=>{if(!res.headersSent) res.status(err.status === 413 ? 413 : 400).json({error:'Invalid request'});});
  return {server,provider,catalog,close:()=>{server.close(); server.closeAllConnections();}};
}
if(process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const gateway = createGateway({baseUrl:process.env.CHRONICLE_MCP_URL,passwordHash:process.env.CHRONICLE_MCP_PASSWORD_HASH,storePath:process.env.CHRONICLE_MCP_STORE || '/data/oauth.json',snapshot:JSON.parse(readFileSync(process.env.CHRONICLE_MCP_SNAPSHOT || '/app/snapshot.json','utf8')),trustProxy:process.env.CHRONICLE_MCP_TRUST_PROXY === '1'});
  gateway.server.listen(Number(process.env.PORT || 8792),process.env.HOST || '127.0.0.1',()=>console.log('Chronicle private MCP ready'));
  process.on('SIGINT',()=>gateway.close()); process.on('SIGTERM',()=>gateway.close());
}
