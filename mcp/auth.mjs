import {randomBytes, createHash, scryptSync, timingSafeEqual} from 'node:crypto';
import {readFileSync, writeFileSync, renameSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {InvalidClientMetadataError, InvalidGrantError, InvalidTokenError, InvalidScopeError, InvalidTargetError, InvalidRequestError} from '@modelcontextprotocol/sdk/server/auth/errors.js';

const random = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('hex');
const now = () => Math.floor(Date.now()/1000);
export const SCOPES = ['chronicle:read'];

export class PrivateOAuth {
  constructor({baseUrl,passwordHash,storePath}) {
    this.base = baseUrl; this.resource = `${baseUrl}/mcp`; this.passwordHash = passwordHash; this.storePath = storePath;
    this.skipLocalPkceValidation = true;
    this.pending = new Map(); this.codes = new Map(); this.db = {clients:{},tokens:{}};
    try {this.db = JSON.parse(readFileSync(storePath,'utf8'));} catch(e) {if(e.code !== 'ENOENT') throw e;}
    this.clientsStore = {
      getClient:async id => Object.hasOwn(this.db.clients,id) ? this.db.clients[id] : undefined,
      registerClient:async info => {
        if (Object.keys(this.db.clients).length >= 100) throw new InvalidClientMetadataError('Client registration limit reached');
        if (!info.redirect_uris?.length || info.redirect_uris.length > 5 || !info.redirect_uris.every(uri=>this.validRedirect(uri))) throw new InvalidClientMetadataError('Only ChatGPT callback URLs allowed');
        if (!['none','client_secret_post'].includes(info.token_endpoint_auth_method || 'client_secret_post')) throw new InvalidClientMetadataError('Unsupported client authentication');
        if (info.scope && info.scope.split(' ').some(s=>!SCOPES.includes(s))) throw new InvalidScopeError('Read-only service');
        this.db.clients[info.client_id] = info; this.save(); return info;
      }
    };
  }
  validRedirect(uri) {
    try {
      const u = new URL(uri);
      return !u.hash && !u.username && !u.password && !u.search && u.origin === 'https://chatgpt.com' && (u.pathname === '/connector_platform_oauth_redirect' || /^\/connector\/oauth\/[A-Za-z0-9_-]+$/.test(u.pathname));
    } catch {return false;}
  }
  save() {
    for (const [k,v] of Object.entries(this.db.tokens)) if(v.expiresAt <= now()) delete this.db.tokens[k];
    mkdirSync(dirname(this.storePath),{recursive:true,mode:0o700});
    writeFileSync(`${this.storePath}.tmp`,JSON.stringify(this.db),{mode:0o600}); renameSync(`${this.storePath}.tmp`,this.storePath);
  }
  resourceCheck(resource) {
    if (resource?.href !== this.resource) throw new InvalidTargetError('Resource must be this Chronicle MCP endpoint');
  }
  async authorize(client,params,res) {
    this.resourceCheck(params.resource);
    const scopes = params.scopes?.length ? params.scopes : SCOPES;
    if (scopes.length !== 1 || scopes[0] !== SCOPES[0]) throw new InvalidScopeError('Only chronicle:read allowed');
    if (!/^[A-Za-z0-9_-]{43}$/.test(params.codeChallenge || '')) throw new InvalidRequestError('PKCE S256 required');
    for (const [id,p] of this.pending) if(p.expires < now()) this.pending.delete(id);
    if(this.pending.size >= 100) throw new InvalidRequestError('Too many pending logins');
    const id = random(), csrf = random();
    this.pending.set(id,{...params,clientId:client.client_id,scopes,csrf:hash(csrf),expires:now()+300,attempts:0});
    res.setHeader('Set-Cookie',`chronicle_mcp_login=${csrf}; Path=${new URL(this.base).pathname}; HttpOnly; SameSite=Lax; Max-Age=300${this.base.startsWith('https:')?'; Secure':''}`);
    res.type('html').send(this.loginPage(id));
  }
  loginPage(id,failed = false) {
    return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Chronicle 私人授权</title><style>body{font:17px/1.7 system-ui;background:#edf0ed;color:#172a23;margin:0;padding:32px}main{max-width:560px;margin:5vh auto;background:white;padding:28px;border-radius:16px}label,input{display:block}input{box-sizing:border-box;width:100%;font:inherit;padding:10px;margin:12px 0}button{font:inherit;padding:9px 20px;margin-right:12px}p{overflow-wrap:anywhere}.error{color:#a00}</style><main><h1>Chronicle 私人讨论接口</h1><p>授权 ChatGPT 读取已发布的项目设定、计划、代码及报告快照。不能修改项目、运行命令、操控游戏或读取玩家存档。项目内容会在你调用工具时发送给 ChatGPT。</p>${failed?'<p class="error" role="alert">口令错误，请重试。</p>':''}<form method="post" action="${this.base}/login"><input type="hidden" name="transaction" value="${id}"><label for="password">专用访问口令</label><input id="password" name="password" type="password" autocomplete="current-password" maxlength="200" required><p>从本机 Chronicle 私人连接信息文件获取口令，只在本页输入，不要发到聊天中。</p><button name="decision" value="allow">授权只读访问</button><button name="decision" value="deny" formnovalidate>取消</button></form></main></html>`;
  }
  login(req,res) {
    const id = req.body.transaction, p = this.pending.get(id);
    const cookie = /(?:^|;\s*)chronicle_mcp_login=([^;]+)/.exec(req.headers.cookie || '')?.[1];
    if(!p || p.expires < now() || !cookie || hash(cookie) !== p.csrf || req.headers.origin !== new URL(this.base).origin) return res.status(403).send('授权页面失效，请返回 ChatGPT 重新连接。');
    const redirect = new URL(p.redirectUri); redirect.searchParams.set('iss',this.base);
    if(p.state) redirect.searchParams.set('state',p.state);
    if(req.body.decision === 'deny') {this.pending.delete(id); redirect.searchParams.set('error','access_denied'); return res.redirect(303,redirect.href);}
    if(req.body.decision !== 'allow') return res.status(400).send('Invalid decision');
    const [salt,expected] = this.passwordHash.split(':');
    const supplied = scryptSync(String(req.body.password || '').slice(0,200),salt,32);
    if(++p.attempts > 5 || !timingSafeEqual(supplied,Buffer.from(expected,'hex'))) {
      if(p.attempts >= 5) this.pending.delete(id);
      return res.status(403).type('html').send(this.loginPage(id,true));
    }
    const code = random(); this.pending.delete(id);
    for(const [k,v] of this.codes) if(v.expires < now()) this.codes.delete(k);
    this.codes.set(hash(code),{...p,expires:now()+60});
    redirect.searchParams.set('code',code); return res.redirect(303,redirect.href);
  }
  getCode(client,code) {
    const grant = this.codes.get(hash(code));
    if(!grant || grant.clientId !== client.client_id || grant.expires < now()) throw new InvalidGrantError('Invalid authorization code');
    return grant;
  }
  async challengeForAuthorizationCode(client,code) {return this.getCode(client,code).codeChallenge;}
  async exchangeAuthorizationCode(client,code,verifier,redirectUri,resource) {
    const grant = this.getCode(client,code); this.resourceCheck(resource);
    if(redirectUri !== grant.redirectUri) throw new InvalidGrantError('Callback mismatch');
    // Ask the SDK to forward the verifier; the provider enforces S256 itself.
    if(!/^[A-Za-z0-9._~-]{43,128}$/.test(verifier || '') || createHash('sha256').update(verifier).digest('base64url') !== grant.codeChallenge) throw new InvalidGrantError('PKCE mismatch');
    this.codes.delete(hash(code)); return this.issue(client.client_id,grant.scopes);
  }
  issue(clientId,scopes,family = random()) {
    this.save();
    if(Object.keys(this.db.tokens).length > 1000) throw new InvalidGrantError('Too many active sessions');
    const access = random(), refresh = random(); const common = {clientId,scopes,resource:this.resource,family};
    this.db.tokens[hash(access)] = {...common,kind:'access',expiresAt:now()+3600};
    this.db.tokens[hash(refresh)] = {...common,kind:'refresh',expiresAt:now()+30*86400}; this.save();
    return {access_token:access,token_type:'Bearer',expires_in:3600,refresh_token:refresh,scope:scopes.join(' ')};
  }
  async exchangeRefreshToken(client,token,scopes,resource) {
    this.resourceCheck(resource); const grant = this.db.tokens[hash(token)];
    if(!grant || grant.kind !== 'refresh' || grant.clientId !== client.client_id || grant.expiresAt <= now()) throw new InvalidGrantError('Invalid refresh token');
    if(scopes?.some(s=>!grant.scopes.includes(s))) throw new InvalidScopeError('Cannot increase scope');
    for(const [k,v] of Object.entries(this.db.tokens)) if(v.family === grant.family) delete this.db.tokens[k];
    return this.issue(client.client_id,scopes || grant.scopes,grant.family);
  }
  async verifyAccessToken(token) {
    const grant = this.db.tokens[hash(token)];
    if(!grant || grant.kind !== 'access' || grant.expiresAt <= now() || grant.resource !== this.resource) throw new InvalidTokenError('Invalid access token');
    return {token,clientId:grant.clientId,scopes:grant.scopes,expiresAt:grant.expiresAt,resource:new URL(grant.resource)};
  }
  async revokeToken(client,{token}) {
    const grant = this.db.tokens[hash(token)]; if(!grant || grant.clientId !== client.client_id) return;
    for(const [k,v] of Object.entries(this.db.tokens)) if(v.family === grant.family) delete this.db.tokens[k]; this.save();
  }
}
