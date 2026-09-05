# H1 地点美术样例来源

日期：2026-09-05。

## 文件与使用范围

- 文件：`assets/world/reed_bank_landing_v1.png`，1536 × 1024。
- 工具：Codex 内置 imagegen；没有使用付费 API 脚本、输入参考图片或备用素材。
- 原始输出：`$CODEX_HOME/generated_images/019ebcb5-52c8-7163-88a8-7b5e49c7b379/exec-e6966911-e28b-4b91-b724-19f074efda1c.png`，原文件保留。
- 项目内使用：生成区域「区域」页，在苇岸聚落显示；不用于冒充其他聚落的独立美术。
- 实现状态：静态地点氛围样例，画中天气、居民、船只和货物不是实时实体投影。界面明确注明这一点。
- 权利记录：为本项目新生成，未指定在世画家风格或已有游戏角色；不是对输出独占版权或第三方权利零风险的保证。正式公开前继续审核赛事的 AI 工具披露要求。

## 最终提示词

```text
Use case: stylized-concept. Asset type: original environment illustration for Chronicle, a grounded text-and-image emergent-world adventure game. Create one finished landscape image, wide 3:2 composition. Subject: a small working reed-bank river settlement in a weathered fantasy frontier, viewed at human eye height from a muddy commons toward a modest wooden landing. Reed bundles drying, patched nets, a low timber storehouse, two simple working boats tied at the landing, footpath disappearing upriver behind buildings. Tiny distant indistinct residents carrying baskets, not heroic characters. This is a place people earn their living, with evidence of maintenance and wear; no dramatic magical event. Hand-painted gouache and restrained ink details, readable substantial shapes, atmospheric depth, muted slate teal water, moss grey and ochre timber, modest warm window lights under an overcast sky. Evoke curiosity about the upstream road and shelter to return to. This will appear next to a dark charcoal game UI; no UI itself, no map, no lettering, no logos, no watermark, no ornamental border, no recognizable existing franchise designs. Keep main structures centrally composed so the picture is readable when scaled to 420 pixels wide. No close-up faces or photorealism.
```

## 视觉技术边界

先用可读的区域拓扑、地点画与图文行动界面验证方向，不转向大型自由视角 3D。画面必须服从地点辨识与决策，实时状态用界面明确表达；不能用生成插画数量替代人物、实物与道路因果。

既有字体 `assets/fonts/SourceHanSerifSC-VF.ttf` 使用 [Adobe 思源宋体项目](https://github.com/adobe-fonts/source-han-serif)，已补充上游 [OFL 1.1 许可文件](https://github.com/adobe-fonts/source-han-serif/blob/release/LICENSE.txt)。该许可不覆盖 `素材包` 里的其他资产，备用库继续排除在导出外。
