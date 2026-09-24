import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash,scryptSync} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import http from 'node:http';
import {createGateway} from '../server.mjs';
import {Catalog,allowedPath,validateDocument,PLAN} from '../catalog.mjs';
import {buildSnapshot} from '../snapshot.mjs';
import {runCheck,authorize,post,register} from '../check.mjs';

const dir = mkdtempSync(join(tmpdir(),'chronicle-mcp-test-'));
const password = 'fixture-password-not-a-real-secret', salt = 'a'.repeat(32);
const passwordHash = `${salt}:${scryptSync(password,salt,32).toString('hex')}`;
const doc = (path,content) => ({path,content,sha256:createHash('sha256').update(content).digest('hex')});
const snapshot = {schema:1,commit:'a'.repeat(40),publishedAt:'2026-09-24T00:00:00Z',documents:[doc(PLAN,'# RF6\nHuman experience remains unvalidated.\nDo not confuse tests with play.'),doc('chronicle-godot/scripts/example.gd','extends RefCounted\n# food and travel') ]};
let gateway,base;
before(async()=>{
  const reserve = http.createServer(); await new Promise(r=>reserve.listen(0,'127.0.0.1',r));
  const port = reserve.address().port; await new Promise(r=>reserve.close(r)); base = `http://127.0.0.1:${port}/chronicle-mcp`;
  gateway = createGateway({baseUrl:base,passwordHash,storePath:join(dir,'oauth.json'),snapshot,disableRateLimits:true});
  await new Promise(r=>gateway.server.listen(port,'127.0.0.1',r));
});
after(()=>{gateway.close(); rmSync(dir,{recursive:true,force:true});});

test('allowlist rejects secrets, saves, traversal, binary assets and working directories',()=>{
  for(const path of ['../texts/a.md','texts/../AGENTS.md','C:/secret.md','texts\\a.md','/texts/a.md','texts//a.md','work/a.md','outputs/report.md','chronicle-godot/.godot/a.gd','texts/private/a.md','texts/token.md','chronicle-godot/data/manual.json','chronicle-godot/art/image.png','.env','mcp/auth.mjs']) assert.equal(allowedPath(path),false,path);
  assert.equal(allowedPath(PLAN),true); assert.equal(allowedPath('chronicle-godot/data/test.json'),true);
  assert.throws(()=>validateDocument('texts/source.md','-----BEGIN PRIVATE KEY-----'));
  assert.throws(()=>validateDocument('texts/source.md','a\0b'));
});
test('catalog returns bounded lines, literal search and immutable commit citations',()=>{
  const c = new Catalog(snapshot);
  assert.equal(c.fetch(PLAN,2,1).text,'Human experience remains unvalidated.');
  assert.equal(c.fetch(PLAN,2,1).nextLine,3);
  assert.match(c.fetch(PLAN).url,/#L1$/);
  assert.equal(c.search('food travel').total,1);
  assert.equal(c.search('.*').total,0);
  assert.equal(c.list('',0,1).nextOffset,1);
  assert.throws(()=>c.fetch('../../secret'));
  assert.throws(()=>new Catalog({...snapshot,documents:[{...snapshot.documents[0],content:'changed'}]}));
});
test('snapshot reads committed blobs, never untracked, dirty content or symlink targets',()=>{
  const repo = join(dir,'repo'); mkdirSync(repo);
  const git = args=>execFileSync('git',args,{cwd:repo,stdio:'pipe'});
  git(['init']); git(['config','user.name','Test']); git(['config','user.email','test@example.invalid']);
  mkdirSync(join(repo,'texts')); writeFileSync(join(repo,'texts/a.md'),'committed');
  git(['add','.']); git(['commit','-m','fixture']);
  writeFileSync(join(repo,'texts/a.md'),'dirty-not-published'); writeFileSync(join(repo,'texts/untracked.md'),'private');
  const s = buildSnapshot(repo); assert.equal(s.documents.length,1); assert.equal(s.documents[0].content,'committed');
  const oid = git(['hash-object','-w','--stdin']);
  // Git symlink entry can be tested without Windows symlink privileges.
  git(['update-index','--add','--cacheinfo',`120000,${oid.toString().trim()},texts/link.md`]); git(['commit','-m','symlink']);
  assert.equal(buildSnapshot(repo).documents.length,1);
});
test('full SDK + OAuth round trip is authenticated, read-only and revocable',async()=>{
  const result = await runCheck(base,password); assert.equal(result.documentCount,2); assert.equal(result.readOnly,true);
});
test('discovery works at canonical RFC paths and rejects alien origins, hosts and callbacks',async()=>{
  const root = new URL(base).origin;
  assert.equal((await fetch(root+'/.well-known/oauth-authorization-server/chronicle-mcp')).status,200);
  assert.equal((await fetch(root+'/.well-known/oauth-protected-resource/chronicle-mcp/mcp')).status,200);
  assert.equal((await fetch(base+'/mcp',{headers:{Origin:'https://evil.example'}})).status,403);
  assert.equal((await register(base,'https://evil.example/callback')).status,400);
  assert.equal((await register(base,'https://chatgpt.com/connector_platform_oauth_redirect?evil=1')).status,400);
  const status = await new Promise(resolve=>{const req = http.get(base+'/health',{headers:{Host:'evil.example'}},res=>{res.resume();resolve(res.statusCode);});req.on('error',e=>{throw e;});});
  assert.equal(status,403);
});
test('code exchange checks resource, PKCE, client and exact redirect; codes are one-use',async()=>{
  const g = await authorize(base,password);
  assert.equal((await post(base,'/token',{...g.exchange,resource:'https://evil.example/mcp'})).status,400);
  assert.equal((await post(base,'/token',{...g.exchange,redirect_uri:'https://chatgpt.com/connector/oauth/different'})).status,400);
  const other = await (await register(base)).json();
  assert.equal((await post(base,'/token',{...g.exchange,client_id:other.client_id})).status,400);
  const ok = await post(base,'/token',g.exchange); assert.equal(ok.status,200);
  assert.equal((await post(base,'/token',g.exchange)).status,400);
});
test('login requires CSRF cookie, correct origin and correct password; cancellation has issuer',async()=>{
  const client = await (await register(base)).json();
  const params = {client_id:client.client_id,response_type:'code',code_challenge:'a'.repeat(43),code_challenge_method:'S256',resource:base+'/mcp'};
  const page = await fetch(base+'/authorize?'+new URLSearchParams(params));
  const transaction = /name="transaction" value="([^"]+)"/.exec(await page.text())[1];
  const cookie = page.headers.get('set-cookie').split(';')[0];
  assert.equal((await post(base,'/login',{transaction,password,decision:'allow'},{Origin:new URL(base).origin})).status,403);
  assert.equal((await post(base,'/login',{transaction,password:'wrong',decision:'allow'},{Origin:new URL(base).origin,Cookie:cookie})).status,403);
  assert.equal((await post(base,'/login',{transaction,password,decision:'allow'},{Origin:'https://evil.example',Cookie:cookie})).status,403);
  const denied = await post(base,'/login',{transaction,decision:'deny'},{Origin:new URL(base).origin,Cookie:cookie});
  assert.equal(denied.status,303); assert.equal(new URL(denied.headers.get('location')).searchParams.get('iss'),base);
});
test('refresh rejects scope escalation, rotates, persists and revokes the family',async()=>{
  const g = await authorize(base,password), response = await post(base,'/token',g.exchange), tokens = await response.json();
  const params = {client_id:g.client.client_id,grant_type:'refresh_token',refresh_token:tokens.refresh_token,resource:base+'/mcp'};
  assert.equal((await post(base,'/token',{...params,scope:'chronicle:write'})).status,400);
  assert.equal((await post(base,'/token',{...params,resource:'https://other.example/mcp'})).status,400);
  const refreshed = await post(base,'/token',params); assert.equal(refreshed.status,200); const next = await refreshed.json();
  assert.equal((await post(base,'/token',params)).status,400);
  await assert.rejects(()=>gateway.provider.verifyAccessToken(tokens.access_token));
  const disk = readFileSync(join(dir,'oauth.json'),'utf8'); assert.ok(!disk.includes(next.access_token)); assert.ok(!disk.includes(next.refresh_token)); assert.ok(!disk.includes(password));
  await post(base,'/revoke',{client_id:g.client.client_id,token:next.refresh_token});
  await assert.rejects(()=>gateway.provider.verifyAccessToken(next.access_token));
});
test('arbitrary authorization scopes and PKCE plain are rejected',async()=>{
  const client = await (await register(base)).json();
  const params = {client_id:client.client_id,response_type:'code',code_challenge:'a'.repeat(43),code_challenge_method:'S256',resource:base+'/mcp',scope:'chronicle:write'};
  const denied = await fetch(base+'/authorize?'+new URLSearchParams(params),{redirect:'manual'});
  assert.equal(denied.status,302);
  assert.equal(new URL(denied.headers.get('location')).searchParams.get('iss'),base);
  const r = await fetch(base+'/authorize?'+new URLSearchParams({...params,scope:'chronicle:read',code_challenge_method:'plain'}),{redirect:'manual'});
  assert.notEqual(r.status,200);
});
