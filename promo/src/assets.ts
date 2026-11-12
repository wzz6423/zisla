import claudeLogo from '../../mac/Resources/BrandIcons/claude-color.svg';
import codexLogo from '../../mac/Resources/BrandIcons/codex-color.svg';
import geminiLogo from '../../mac/Resources/BrandIcons/gemini-color.svg';
import githubMark from '../../mac/Resources/BrandIcons/github-mark.svg';
import zislaIcon from '../../web/public/assets/zisla-icon.png';
import type {Provider} from './content';

// 品牌图标直接引用应用自带的资源（lobehub/lobe-icons，MIT），不在 promo 里另存副本
export const providerLogo: Record<Provider, string> = {
  claude: claudeLogo,
  codex: codexLogo,
  gemini: geminiLogo,
};

export {githubMark, zislaIcon};
