import assert from 'node:assert/strict';
import {createHash, randomBytes} from 'node:crypto';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';

export async function post(base,path,data,headers = {}) {
  return fetch(base+path,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded',...headers},body:new URLSearchParams(data),redirect:'manual',signal:AbortSignal.timeout(20000)});
}
export async function register(base,redirect = 'https://chatgpt.com/connector_platform_oauth_redirect') {
  return fetch(base+'/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({client_name:'Chronicle verification',redirect_uris:[redirect],token_endpoint_auth_method:'none',grant_types:['authorization_code','refresh_token'],response_types:['code']}),signal:AbortSignal.timeout(20000)});
}
export async function authorize(base,password,existingClient) {
  const registration = existingClient ? null : await register(base);
  if(registration) assert.equal(registration.status,201);
  const client = existingClient || await registration.json();
  const verifier = randomBytes(32).toString('base64url');
  const params = {client_id:client.client_id,redirect_uri:client.redirect_uris[0],response_type:'code',code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256',resource:base+'/mcp',scope:'chronicle:read',state:'verification'};
  const page = await fetch(base+'/authorize?'+new URLSearchParams(params),{redirect:'manual',signal:AbortSignal.timeout(20000)});
  assert.equal(page.status,200);
  const transaction = /name="transaction" value="([^"]+)"/.exec(await page.text())[1];
  const cookie = page.headers.get('set-cookie').split(';')[0];
  const login = await post(base,'/login',{transaction,password,decision:'allow'},{Cookie:cookie,Origin:new URL(base).origin});
  assert.equal(login.status,303);
  const redirect = new URL(login.headers.get('location'));
  assert.equal(redirect.searchParams.get('state'),'verification');
  assert.equal(redirect.searchParams.get('iss'),base);
  return {client,exchange:{client_id:client.client_id,grant_type:'authorization_code',code:redirect.searchParams.get('code'),code_verifier:verifier,redirect_uri:params.redirect_uri,resource:base+'/mcp'}};
}
export async function runCheck(base,password,existingClient) {
  const health = await fetch(base+'/health',{signal:AbortSignal.timeout(20000)}); assert.equal(health.status,200);
  assert.equal((await health.json()).service,'chronicle-private-mcp');
  const blocked = await fetch(base+'/mcp'); assert.equal(blocked.status,401);
  assert.match(blocked.headers.get('www-authenticate'),/resource_metadata=/);
  const metadata = await (await fetch(base+'/.well-known/oauth-protected-resource')).json(); assert.equal(metadata.resource,base+'/mcp');
  const auth = await (await fetch(base+'/.well-known/oauth-authorization-server')).json(); assert.ok(auth.code_challenge_methods_supported.includes('S256'));
  const g = await authorize(base,password,existingClient);
  assert.equal((await post(base,'/token',{...g.exchange,code_verifier:'wrong'.repeat(12)})).status,400);
  const response = await post(base,'/token',g.exchange); assert.equal(response.status,200);
  let tokens = await response.json(); const client = new Client({name:'chronicle-public-check',version:'1.0.0'});
  try {
    await client.connect(new StreamableHTTPClientTransport(new URL(base+'/mcp'),{requestInit:{headers:{Authorization:`Bearer ${tokens.access_token}`}}}));
    const list = await client.listTools(); assert.deepEqual(list.tools.map(t=>t.name).sort(),['fetch','list_files','project_overview','search']);
    assert.ok(list.tools.every(t=>t.annotations.readOnlyHint && t.annotations.destructiveHint === false));
    const overviewResult = await client.callTool({name:'project_overview',arguments:{}}); assert.ok(!overviewResult.isError);
    const overview = JSON.parse(overviewResult.content[0].text);
    const search = await client.callTool({name:'search',arguments:{query:'RF6',prefix:'texts/v5'}}); assert.ok(!search.isError); assert.ok(JSON.parse(search.content[0].text).results.length);
    const file = await client.callTool({name:'fetch',arguments:{id:overview.entryPoints[0].path,line_count:30}}); assert.ok(!file.isError);
    const denied = await client.callTool({name:'fetch',arguments:{id:'../../private/connection.json'}}); assert.equal(denied.isError,true);
    const noWrite = await client.callTool({name:'write_file',arguments:{path:'AGENTS.md',text:'must never execute'}}); assert.equal(noWrite.isError,true);
    const refresh = await post(base,'/token',{client_id:g.client.client_id,grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource:base+'/mcp'}); assert.equal(refresh.status,200);
    const oldAccess = tokens.access_token; tokens = await refresh.json();
    assert.equal((await fetch(base+'/mcp',{headers:{Authorization:`Bearer ${oldAccess}`}})).status,401);
    const revoked = await post(base,'/revoke',{client_id:g.client.client_id,token:tokens.refresh_token}); assert.equal(revoked.status,200);
    assert.equal((await fetch(base+'/mcp',{headers:{Authorization:`Bearer ${tokens.access_token}`}})).status,401);
    return {ok:true,baseUrl:base,commit:overview.commit,documentCount:overview.documentCount,tools:list.tools.map(t=>t.name),unauthenticated401:true,pkce:true,readOnly:true,pathIsolation:true,refreshAndRevoke:true,checkedAt:new Date().toISOString(),client:g.client};
  } finally {
    await client.close();
    await post(base,'/revoke',{client_id:g.client.client_id,token:tokens.refresh_token});
  }
}
