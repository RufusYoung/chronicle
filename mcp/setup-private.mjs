import {mkdirSync, existsSync, writeFileSync} from 'node:fs';
import {resolve, join, sep} from 'node:path';
import {execFileSync} from 'node:child_process';
import {randomBytes, scryptSync} from 'node:crypto';

const base = process.argv[2] || 'https://120.27.141.243/chronicle-mcp';
const directory = resolve(process.argv[3] || 'C:/code/game/chronicle-private/mcp');
const repo = resolve(import.meta.dirname,'..');
if(directory === repo || directory.startsWith(repo+sep)) throw new Error('Private credentials must live outside the repository');
if(new URL(base).protocol !== 'https:' || !/^\/[a-z0-9-]+$/.test(new URL(base).pathname)) throw new Error('Use a public HTTPS base URL');
if(existsSync(join(directory,'connection.json'))) throw new Error('Credentials already exist; refusing to overwrite');
mkdirSync(directory,{recursive:true,mode:0o700});
if(process.platform === 'win32') {
  const sid = execFileSync('powershell',['-NoProfile','-Command','[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value'],{encoding:'utf8'}).trim();
  execFileSync('icacls',[directory,'/inheritance:r','/grant:r',`*${sid}:(OI)(CI)F`,'*S-1-5-18:(OI)(CI)F']);
}
const password = randomBytes(24).toString('base64url'), salt = randomBytes(16).toString('hex');
const passwordHash = `${salt}:${scryptSync(password,salt,32).toString('hex')}`;
writeFileSync(join(directory,'gateway.env'),`CHRONICLE_MCP_URL=${base}\nCHRONICLE_MCP_PASSWORD_HASH=${passwordHash}\nCHRONICLE_MCP_TRUST_PROXY=1\nHOST=0.0.0.0\nPORT=8792\n`,{mode:0o600,flag:'wx'});
writeFileSync(join(directory,'connection.json'),JSON.stringify({baseUrl:base,password},null,2),{mode:0o600,flag:'wx'});
writeFileSync(join(directory,'Chronicle-MCP-私人连接信息.txt'),`Chronicle 私人只读 MCP\n\n地址：${base}/mcp\n认证：OAuth\n客户端注册：DCR（动态注册），Client ID 和 Client Secret 留空\n\n私人访问口令：${password}\n\n只在 Chronicle 授权网页输入口令。不要发送到 GPT 对话、提交到 Git 或分享。\n接口只能读取已发布的项目快照，不能操控游戏或修改存档。\n`,{mode:0o600,flag:'wx'});
console.log(`Private credentials created in ${directory}; secrets were not printed.`);
