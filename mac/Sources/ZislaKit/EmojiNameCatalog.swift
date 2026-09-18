import Foundation
import NaturalLanguage
import ZislaCore

/// Emoji name catalog for the clipboard assistant.
///
/// Curated aliases stay first for the established short names, while the
/// bundled CLDR catalog provides the complete stable Emoji roster and all
/// supported interface languages without depending on the host macOS version.
///
/// Matching rules implemented in `emoji(for:)` and `emojiCandidates(for:)`:
/// - Case-insensitive for Latin names ("Fire" matches "fire").
/// - Surrounding colons are stripped, so Slack/GitHub style shortcodes work
///   (`:fire:`, `:thumbs_up:`).
/// - Underscores and hyphens inside a query read as spaces, and multi-word
///   names are also matched with spaces removed (`:thumbsup:` matches
///   "thumbs up").
/// - Runs of whitespace collapse into single spaces.
/// - Exact aliases resolve first. Near names use input-method-style candidate
///   ranking only when they do not look like a sentence.
public enum EmojiNameCatalog {
    /// Every alias across all entries must be unique so lookups stay
    /// deterministic; dictionary iteration order is not guaranteed. Internal
    /// (not private) so the test target can audit the data with `@testable`.
    static let entries: [String: (english: [String], chinese: [String])] = [
        // MARK: Smileys

        "😀": (["grinning face", "grinning", "big grin", "smiley", "smiley face"], ["咧嘴笑", "大笑", "呲牙"]),
        "😃": (["grinning face with big eyes", "haha"], ["哈哈", "嘿嘿"]),
        "😄": (["grinning face with smiling eyes", "smile", "happy"], ["开心", "笑得开心"]),
        "😁": (["beaming face with smiling eyes"], ["咧嘴笑脸", "灿烂笑"]),
        "😆": (["grinning squinting face", "laughing", "satisfied"], ["眯眼笑"]),
        "😅": (["grinning face with sweat", "sweat smile"], ["尴尬笑", "流汗笑"]),
        "🤣": (["rolling on the floor laughing", "rofl"], ["笑翻了", "笑死"]),
        "😂": (["face with tears of joy", "joy", "tears of joy"], ["笑哭", "笑哭了"]),
        "🤩": (["star-struck", "star struck", "excited", "star eyes"], ["激动", "星星眼"]),
        "🙂": (["slightly smiling face", "slight smile"], ["微笑", "微微一笑"]),
        "😉": (["winking face", "wink"], ["眨眼", "抛媚眼"]),
        "😊": (["smiling face with smiling eyes", "blush"], ["面带微笑", "微笑眼睛"]),
        "🥰": (["smiling face with hearts", "smiling face with three hearts", "love face"], ["被爱", "陶醉"]),
        "😍": (["smiling face with heart-eyes", "heart eyes"], ["花痴", "爱心眼"]),
        "😘": (["face blowing a kiss", "kiss", "blowing a kiss"], ["飞吻"]),
        "😗": (["kissing face"], ["亲亲", "嘟嘴"]),
        "😙": (["kissing face with smiling eyes"], ["微笑亲亲"]),
        "😜": (["winking face with tongue", "wink tongue", "playful"], ["调皮", "吐舌眨眼"]),
        "😛": (["face with tongue", "tongue"], ["吐舌头"]),
        "🤪": (["zany face", "zany", "goofy", "crazy"], ["搞怪", "疯狂"]),
        "😋": (["face savoring food", "yum", "delicious"], ["好吃", "美味"]),
        "🤤": (["drooling face", "drooling", "drool"], ["流口水", "馋"]),
        "🤨": (["face with raised eyebrow", "raised eyebrow", "suspicious"], ["挑眉", "怀疑"]),
        "😐": (["neutral face"], ["面无表情"]),
        "😑": (["expressionless face"], ["无语", "木讷"]),
        "🙄": (["face with rolling eyes", "eye roll", "rolling eyes"], ["翻白眼"]),
        "😏": (["smirking face", "smirk"], ["得意", "坏笑"]),
        "😔": (["pensive face", "pensive"], ["沮丧", "失落"]),
        "😪": (["sleepy face", "sleepy"], ["困", "瞌睡"]),
        "😴": (["sleeping face", "sleeping", "sleep"], ["睡着了", "睡觉", "睡"]),
        "😌": (["relieved face", "relieved"], ["如释重负", "舒心"]),
        "😖": (["confounded face"], ["困惑", "为难"]),
        "😕": (["confused face", "confused"], ["迷惑", "不解"]),
        "🙃": (["upside-down face", "upside down face"], ["倒脸", "颠倒笑脸"]),
        "🫠": (["melting face", "melting"], ["融化了", "热化了"]),
        "🫡": (["saluting face", "salute"], ["敬礼"]),
        "🥹": (["face holding back tears"], ["强忍泪水"]),
        "🤗": (["face hugging", "hug", "hugging"], ["拥抱", "抱抱"]),
        "🤭": (["face with hand over mouth", "giggle"], ["偷笑", "捂嘴"]),
        "🫢": (["face with open eyes and hand over mouth"], ["捂嘴惊讶"]),
        "🤫": (["shushing face", "shush", "quiet"], ["嘘", "安静"]),
        "🤔": (["thinking face", "thinking", "think"], ["思考", "想一想"]),
        "🤐": (["zipper-mouth face", "zipper mouth"], ["拉链嘴", "守口如瓶"]),
        "😶": (["face without mouth", "no mouth"], ["沉默", "闭嘴"]),
        "🫥": (["dotted line face", "invisible"], ["隐身", "消失"]),
        "😬": (["grimacing face"], ["尴尬", "咬牙"]),
        "🤥": (["lying face", "liar"], ["说谎", "长鼻子"]),
        "😒": (["unamused face", "unamused", "meh"], ["不高兴", "嫌弃"]),
        "🥲": (["smiling face with tear"], ["含泪微笑"]),
        "😥": (["sad but relieved face"], ["失望落泪"]),
        "😳": (["flushed face", "flushed", "embarrassed"], ["脸红", "害羞"]),
        "🥺": (["pleading face", "pleading"], ["委屈", "求你了", "可怜"]),
        "😶‍🌫️": (["face in clouds", "face in the clouds"], ["云里雾里"]),
        "😵‍💫": (["face with spiral eyes"], ["晕头转向"]),
        "😱": (["face screaming in fear", "scream"], ["惊恐尖叫", "尖叫"]),
        "😨": (["fearful face", "fearful", "scared", "afraid"], ["害怕", "恐惧"]),
        "😰": (["anxious face with sweat", "anxious", "nervous"], ["紧张", "冷汗"]),
        "😢": (["crying face", "crying", "sad"], ["流泪", "哭了"]),
        "😭": (["loudly crying face", "sob", "bawling"], ["大哭", "嚎啕大哭"]),
        "😤": (["face with steam from nose", "triumph", "steam from nose"], ["气鼓鼓", "不服"]),
        "😠": (["angry face", "angry"], ["生气", "愤怒"]),
        "😡": (["enraged face", "rage"], ["暴怒", "气死了"]),
        "🤬": (["face with symbols on mouth", "cursing", "swearing"], ["骂人", "爆粗口"]),
        "🥵": (["hot face", "overheated", "feeling hot"], ["热死了", "热"]),
        "🥶": (["cold face", "freezing", "cold"], ["冷死了", "冷"]),
        "🥴": (["woozy face", "woozy", "tipsy"], ["晕乎乎", "喝断片"]),
        "😵": (["face with crossed-out eyes", "knocked out"], ["眼冒金星", "晕倒"]),
        "🤯": (["exploding head", "mind blown"], ["炸了", "震惊到爆炸"]),
        "🤠": (["cowboy hat face", "cowboy"], ["牛仔"]),
        "🥳": (["partying face", "party face", "party"], ["派对", "庆祝脸"]),
        "🤓": (["nerd face", "nerd"], ["书呆子", "学霸"]),
        "🧐": (["face with monocle", "monocle"], ["单片眼镜", "审视"]),
        "😲": (["astonished face", "astonished", "shocked"], ["震惊", "惊呆"]),
        "😮": (["face with open mouth", "open mouth", "surprised", "wow"], ["惊讶", "哇"]),
        "😯": (["hushed face", "hushed"], ["目瞪口呆"]),
        "😫": (["tired face", "tired", "weary"], ["累", "好累", "疲惫"]),
        "🥱": (["yawning face", "yawn"], ["打哈欠", "困倦"]),
        "😷": (["face with medical mask", "mask"], ["戴口罩", "口罩"]),
        "🤒": (["face with thermometer"], ["发烧"]),
        "🤕": (["bandaged face", "bandage"], ["受伤"]),
        "🤢": (["nauseated face", "nauseated", "sick"], ["恶心", "想吐"]),
        "🤮": (["face vomiting", "vomit", "puke"], ["吐了", "呕吐"]),
        "🤧": (["sneezing face", "sneeze"], ["打喷嚏", "感冒"]),
        "😈": (["smiling face with horns", "devil", "purple devil"], ["小恶魔"]),
        "👿": (["angry face with horns", "imp", "angry devil"], ["恶魔"]),
        "💀": (["skull"], ["骷髅"]),
        "☠️": (["skull and crossbones", "poison"], ["剧毒", "骷髅旗"]),
        "💩": (["pile of poo", "poop", "poo"], ["便便"]),
        "🤡": (["clown face", "clown"], ["小丑"]),
        "👻": (["ghost"], ["鬼", "幽灵"]),
        "👽": (["alien"], ["外星人"]),
        "🤖": (["robot"], ["机器人"]),
        "🎃": (["jack-o-lantern", "jack o lantern", "halloween"], ["南瓜灯", "万圣节"]),
        "😺": (["grinning cat", "happy cat"], ["开心的猫"]),
        "😹": (["cat with tears of joy", "joy cat"], ["笑哭猫"]),
        "😻": (["smiling cat with heart-eyes", "heart eyes cat"], ["爱心眼猫"]),
        "🥷": (["ninja"], ["忍者"]),
        "🧙": (["mage", "wizard"], ["巫师", "法师"]),
        "🧚": (["fairy"], ["仙女"]),
        "🎅": (["santa claus", "santa"], ["圣诞老人"]),
        "🦸": (["superhero"], ["超级英雄"]),
        "🤦": (["person facepalming", "facepalm"], ["捂脸", "扶额"]),
        "🤷": (["person shrugging", "shrug", "shrugging"], ["耸肩", "不知道"]),

        // MARK: Gestures and body

        "👋": (["waving hand", "wave", "hello", "hi", "bye"], ["挥手", "打招呼", "拜拜"]),
        "🤚": (["raised back of hand"], ["手背"]),
        "✋": (["raised hand", "high five"], ["举手", "击掌"]),
        "🖖": (["vulcan salute", "spock"], ["瓦肯举手礼"]),
        "👌": (["ok hand", "okay hand", "ok", "okay", "perfect"], ["ok", "ok手势", "完美"]),
        "🤌": (["pinched fingers"], ["捏手指"]),
        "✌️": (["victory hand", "victory", "peace", "peace sign"], ["胜利", "耶", "剪刀手"]),
        "🤞": (["crossed fingers", "fingers crossed", "hoping"], ["祈祷手指", "求好运", "交叉手指"]),
        "🤟": (["love-you gesture", "love you gesture", "ily"], ["爱你手势", "爱你"]),
        "🤘": (["sign of the horns", "rock on"], ["摇滚", "摇滚手势"]),
        "🤙": (["call me hand", "call me", "shaka"], ["打电话手势", "call我"]),
        "👈": (["backhand index pointing left", "point left"], ["指向左边"]),
        "👉": (["backhand index pointing right", "point right"], ["指向右边", "你看"]),
        "👆": (["backhand index pointing up", "point up"], ["指向上方", "手指向上"]),
        "👇": (["backhand index pointing down", "point down"], ["指向下方"]),
        "☝️": (["index pointing up", "index finger up", "one"], ["食指向上", "注意"]),
        "✍️": (["writing hand", "writing"], ["写字", "签名"]),
        "👏": (["clapping hands", "clap", "applause"], ["鼓掌", "拍手"]),
        "🙌": (["raising hands", "raised hands", "hooray", "celebration"], ["欢呼", "举双手", "万岁"]),
        "🫶": (["heart hands"], ["比心", "爱心手"]),
        "🫰": (["hand with index finger and thumb crossed", "finger heart", "snap"], ["手指比心", "响指"]),
        "🤲": (["palms up together"], ["双手合十"]),
        "🤝": (["handshake"], ["握手", "合作"]),
        "🙏": (["folded hands", "pray", "please", "thanks", "thank you"], ["祈祷", "合十", "拜托", "感谢", "谢谢"]),
        "👍": (["thumbs up", "like", "yes", "approve"], ["点赞", "竖起大拇指", "大拇指", "棒"]),
        "👎": (["thumbs down", "dislike", "disapprove"], ["差评", "倒竖拇指", "不赞"]),
        "👊": (["oncoming fist", "fist bump", "fist", "punch"], ["碰拳", "拳头"]),
        "✊": (["raised fist"], ["举拳"]),
        "💅": (["nail polish"], ["美甲", "指甲油"]),
        "🤳": (["selfie"], ["自拍"]),
        "💪": (["flexed biceps", "muscle", "strong", "flex"], ["肌肉", "加油", "力量"]),
        "🦾": (["mechanical arm"], ["机械臂"]),
        "🦿": (["mechanical leg"], ["机械腿"]),
        "🦵": (["leg"], ["腿"]),
        "🦶": (["foot"], ["脚"]),
        "👂": (["ear"], ["耳朵"]),
        "👃": (["nose"], ["鼻子"]),
        "🧠": (["brain"], ["大脑", "脑子"]),
        "🫀": (["anatomical heart"], ["心脏"]),
        "🫁": (["lungs"], ["肺"]),
        "🦷": (["tooth"], ["牙齿"]),
        "🦴": (["bone"], ["骨头"]),
        "👀": (["eyes"], ["眼睛", "双眼"]),
        "👁️": (["eye"], ["单眼"]),
        "👅": (["tongue body", "taste"], ["舌头"]),
        "👄": (["mouth"], ["嘴巴"]),
        "🫦": (["biting lip"], ["咬唇"]),

        // MARK: Hearts and symbols

        "❤️": (["red heart", "heart", "love"], ["红心", "爱心", "爱", "心"]),
        "🧡": (["orange heart"], ["橙心", "橙色爱心"]),
        "💛": (["yellow heart"], ["黄心", "黄色爱心"]),
        "💚": (["green heart"], ["绿心", "绿色爱心"]),
        "💙": (["blue heart"], ["蓝心", "蓝色爱心"]),
        "💜": (["purple heart"], ["紫心", "紫色爱心"]),
        "🖤": (["black heart"], ["黑心", "黑色爱心"]),
        "🤍": (["white heart"], ["白心", "白色爱心"]),
        "🤎": (["brown heart"], ["棕心", "棕色爱心"]),
        "💔": (["broken heart", "heartbreak"], ["心碎", "碎了"]),
        "❤️‍🔥": (["heart on fire", "burning heart"], ["燃烧的心"]),
        "❤️‍🩹": (["mending heart"], ["修复的心", "愈合"]),
        "💕": (["two hearts"], ["两颗心"]),
        "💞": (["revolving hearts"], ["旋转的心"]),
        "💘": (["heart with arrow", "cupid"], ["丘比特之箭", "一箭穿心"]),
        "💖": (["sparkling heart"], ["闪亮的心", "闪闪爱心"]),
        "💗": (["growing heart"], ["心动的心"]),
        "💓": (["beating heart", "heartbeat"], ["心跳", "扑通"]),
        "💟": (["heart decoration"], ["爱心装饰"]),
        "💮": (["white flower"], ["白花"]),
        "💯": (["hundred points", "hundred", "100", "perfect score"], ["满分", "一百分"]),
        "💢": (["anger symbol", "anger"], ["生气符号", "青筋"]),
        "💥": (["collision", "boom", "explosion"], ["爆炸", "砰"]),
        "💫": (["dizzy", "dizzy symbol"], ["头晕目眩", "星星环绕"]),
        "💦": (["sweat droplets", "sweat"], ["汗滴", "水滴"]),
        "💨": (["dashing away", "wind", "dash"], ["疾风", "一阵风"]),
        "🕳️": (["hole"], ["洞"]),
        "💬": (["speech balloon", "comment"], ["对话气泡", "留言"]),
        "💭": (["thought balloon", "thought"], ["想法气泡", "心声"]),
        "🗯️": (["right anger bubble"], ["怒气气泡"]),
        "💤": (["zzz", "sleep symbol"], ["呼呼大睡", "zzz"]),

        // MARK: Animals

        "🐶": (["dog face", "dog", "puppy"], ["狗", "小狗", "汪汪"]),
        "🐱": (["cat face", "cat", "kitten"], ["猫", "小猫", "喵"]),
        "🐭": (["mouse face", "mouse"], ["老鼠", "鼠"]),
        "🐹": (["hamster"], ["仓鼠"]),
        "🐰": (["rabbit face", "rabbit", "bunny"], ["兔子", "小兔子", "兔"]),
        "🦊": (["fox"], ["狐狸"]),
        "🐻": (["bear"], ["熊"]),
        "🐻‍❄️": (["polar bear"], ["北极熊"]),
        "🐼": (["panda", "panda bear"], ["熊猫"]),
        "🐨": (["koala"], ["考拉", "树袋熊"]),
        "🐯": (["tiger face", "tiger"], ["老虎", "虎"]),
        "🦁": (["lion", "lion face"], ["狮子"]),
        "🐮": (["cow face", "cow"], ["牛", "奶牛"]),
        "🐷": (["pig face", "pig"], ["猪", "小猪"]),
        "🐸": (["frog"], ["青蛙"]),
        "🐵": (["monkey face", "monkey"], ["猴子", "猴"]),
        "🙈": (["see-no-evil monkey", "see no evil monkey"], ["捂眼猴", "非礼勿视"]),
        "🙉": (["hear-no-evil monkey", "hear no evil monkey"], ["捂耳猴", "非礼勿听"]),
        "🙊": (["speak-no-evil monkey", "speak no evil monkey"], ["捂嘴猴", "非礼勿说"]),
        "🐔": (["chicken", "hen"], ["鸡", "母鸡"]),
        "🐧": (["penguin"], ["企鹅"]),
        "🐦": (["bird"], ["鸟", "小鸟"]),
        "🐤": (["baby chick", "chick"], ["小鸡"]),
        "🦆": (["duck"], ["鸭子"]),
        "🦅": (["eagle"], ["鹰"]),
        "🦉": (["owl"], ["猫头鹰"]),
        "🦇": (["bat"], ["蝙蝠"]),
        "🐺": (["wolf"], ["狼"]),
        "🐗": (["boar"], ["野猪"]),
        "🐴": (["horse face", "horse"], ["马"]),
        "🦄": (["unicorn"], ["独角兽"]),
        "🐝": (["honeybee", "bee"], ["蜜蜂"]),
        "🐛": (["bug", "insect"], ["毛毛虫", "虫子"]),
        "🦋": (["butterfly"], ["蝴蝶"]),
        "🐌": (["snail"], ["蜗牛"]),
        "🐞": (["lady beetle", "ladybug"], ["瓢虫"]),
        "🐜": (["ant"], ["蚂蚁"]),
        "🕷️": (["spider"], ["蜘蛛"]),
        "🪳": (["cockroach"], ["蟑螂"]),
        "🦂": (["scorpion"], ["蝎子"]),
        "🐢": (["turtle", "tortoise"], ["乌龟", "海龟"]),
        "🐍": (["snake", "serpent"], ["蛇"]),
        "🦎": (["lizard"], ["蜥蜴"]),
        "🦖": (["t-rex", "t rex", "trex", "dinosaur"], ["霸王龙", "恐龙"]),
        "🦕": (["sauropod"], ["长颈龙"]),
        "🐙": (["octopus"], ["章鱼"]),
        "🦑": (["squid"], ["鱿鱼"]),
        "🦐": (["shrimp"], ["虾"]),
        "🦞": (["lobster"], ["龙虾"]),
        "🦀": (["crab"], ["螃蟹"]),
        "🐡": (["blowfish", "pufferfish"], ["河豚"]),
        "🐠": (["tropical fish"], ["热带鱼"]),
        "🐟": (["fish"], ["鱼"]),
        "🐬": (["dolphin"], ["海豚"]),
        "🐳": (["spouting whale", "whale"], ["鲸鱼"]),
        "🦈": (["shark"], ["鲨鱼"]),
        "🐊": (["crocodile", "alligator"], ["鳄鱼"]),
        "🦓": (["zebra"], ["斑马"]),
        "🦍": (["gorilla"], ["大猩猩"]),
        "🐘": (["elephant"], ["大象"]),
        "🦛": (["hippopotamus", "hippo"], ["河马"]),
        "🦏": (["rhinoceros", "rhino"], ["犀牛"]),
        "🐪": (["camel"], ["骆驼"]),
        "🦒": (["giraffe"], ["长颈鹿"]),
        "🦘": (["kangaroo"], ["袋鼠"]),
        "🐑": (["ewe", "sheep"], ["羊", "绵羊"]),
        "🐐": (["goat"], ["山羊"]),
        "🐂": (["ox", "bull"], ["公牛"]),
        "🐉": (["dragon"], ["龙", "龙年"]),
        "🐲": (["dragon face"], ["龙头"]),
        "🦃": (["turkey"], ["火鸡"]),
        "🦚": (["peacock"], ["孔雀"]),
        "🦜": (["parrot"], ["鹦鹉"]),
        "🦢": (["swan"], ["天鹅"]),
        "🦩": (["flamingo"], ["火烈鸟"]),
        "🕊️": (["dove", "peace dove"], ["鸽子", "和平鸽"]),
        "🐕‍🦺": (["service dog"], ["服务犬"]),
        "🐈‍⬛": (["black cat"], ["黑猫"]),

        // MARK: Plants and weather

        "🔥": (["fire", "flame", "lit"], ["火", "火焰", "烈焰", "火爆"]),
        "✨": (["sparkles", "shine", "glitter"], ["闪光", "闪耀", "亮晶晶"]),
        "⭐": (["star"], ["星星", "星"]),
        "🌟": (["glowing star"], ["发光的星星", "亮星"]),
        "⚡": (["high voltage", "lightning", "zap", "bolt"], ["闪电", "电力"]),
        "☀️": (["sun", "sunny"], ["太阳", "晴天"]),
        "🌞": (["sun with face"], ["太阳脸"]),
        "⛅": (["sun behind cloud", "partly sunny"], ["多云", "晴间多云"]),
        "☁️": (["cloud"], ["云", "云朵"]),
        "🌈": (["rainbow"], ["彩虹"]),
        "☔": (["umbrella with rain drops", "rain", "rainy", "umbrella"], ["下雨", "雨伞"]),
        "⛄": (["snowman without snow", "snowman"], ["雪人"]),
        "❄️": (["snowflake", "snow"], ["雪花", "下雪"]),
        "🌪️": (["tornado"], ["龙卷风"]),
        "🌫️": (["fog"], ["雾"]),
        "🌡️": (["thermometer"], ["温度计"]),
        "🌙": (["crescent moon", "moon"], ["月亮", "弯月"]),
        "🌕": (["full moon"], ["满月"]),
        "🌑": (["new moon"], ["新月", "黑月"]),
        "🌍": (["globe showing europe-africa", "globe", "earth", "world"], ["地球", "世界"]),
        "🌏": (["globe showing asia-australia", "globe asia"], ["地球亚洲"]),
        "🌎": (["globe showing americas", "globe americas"], ["地球美洲"]),
        "🌋": (["volcano"], ["火山"]),
        "⛰️": (["mountain"], ["山", "高山"]),
        "🏔️": (["snow-capped mountain", "snowy mountain"], ["雪山"]),
        "🏕️": (["camping"], ["露营"]),
        "🏖️": (["beach with umbrella", "beach"], ["沙滩", "海滩"]),
        "🏝️": (["desert island", "island"], ["海岛", "孤岛"]),
        "🌅": (["sunrise"], ["日出"]),
        "🌄": (["sunrise over mountains"], ["山间日出"]),
        "🌇": (["sunset"], ["日落", "黄昏"]),
        "🌆": (["cityscape at dusk"], ["黄昏城市"]),
        "🌃": (["night with stars", "night"], ["夜晚", "夜景"]),
        "🌉": (["bridge at night", "bridge"], ["桥", "大桥"]),
        "🌊": (["water wave", "ocean", "sea"], ["海浪", "大海"]),
        "🌸": (["cherry blossom", "sakura"], ["樱花", "花"]),
        "🌹": (["rose"], ["玫瑰"]),
        "🌷": (["tulip"], ["郁金香"]),
        "🌻": (["sunflower"], ["向日葵"]),
        "🌼": (["blossom", "daisy"], ["雏菊", "小花"]),
        "🥀": (["wilted flower", "wilted"], ["枯萎", "凋谢"]),
        "🌺": (["hibiscus"], ["扶桑花"]),
        "🌱": (["seedling", "sprout"], ["幼苗", "发芽"]),
        "🌲": (["evergreen tree", "pine tree"], ["松树", "松柏"]),
        "🌳": (["deciduous tree", "tree"], ["树", "大树"]),
        "🌴": (["palm tree", "palm"], ["椰子树", "棕榈树"]),
        "🌵": (["cactus"], ["仙人掌"]),
        "🌾": (["sheaf of rice"], ["稻穗"]),
        "🌿": (["herb"], ["香草"]),
        "☘️": (["shamrock"], ["三叶草"]),
        "🍀": (["four leaf clover", "clover", "lucky"], ["四叶草", "幸运草", "好运"]),
        "🍁": (["maple leaf", "maple"], ["枫叶"]),
        "🍂": (["fallen leaf"], ["落叶"]),
        "🍃": (["leaf fluttering in wind", "leaves"], ["绿叶", "风吹叶"]),

        // MARK: Food and drinks

        "🍏": (["green apple"], ["青苹果"]),
        "🍎": (["red apple", "apple"], ["苹果", "红苹果"]),
        "🍐": (["pear"], ["梨"]),
        "🍊": (["tangerine", "orange", "mandarin"], ["橘子", "橙子"]),
        "🍋": (["lemon"], ["柠檬"]),
        "🍌": (["banana"], ["香蕉"]),
        "🍉": (["watermelon"], ["西瓜"]),
        "🍇": (["grapes", "grape"], ["葡萄"]),
        "🍓": (["strawberry"], ["草莓"]),
        "🫐": (["blueberries", "blueberry"], ["蓝莓"]),
        "🍈": (["melon"], ["甜瓜", "哈密瓜"]),
        "🍒": (["cherries", "cherry"], ["樱桃"]),
        "🍑": (["peach"], ["桃子", "水蜜桃"]),
        "🥭": (["mango"], ["芒果"]),
        "🍍": (["pineapple"], ["菠萝", "凤梨"]),
        "🥥": (["coconut"], ["椰子"]),
        "🥝": (["kiwi fruit", "kiwi"], ["猕猴桃", "奇异果"]),
        "🍅": (["tomato"], ["番茄", "西红柿"]),
        "🍆": (["eggplant"], ["茄子"]),
        "🥑": (["avocado"], ["牛油果", "鳄梨"]),
        "🥦": (["broccoli"], ["西兰花"]),
        "🥬": (["leafy green"], ["青菜", "绿叶菜"]),
        "🥒": (["cucumber"], ["黄瓜"]),
        "🌶️": (["hot pepper", "chili", "spicy"], ["辣椒", "辣"]),
        "🌽": (["corn"], ["玉米"]),
        "🥕": (["carrot"], ["胡萝卜"]),
        "🧄": (["garlic"], ["大蒜"]),
        "🧅": (["onion"], ["洋葱"]),
        "🥔": (["potato"], ["土豆", "马铃薯"]),
        "🍠": (["roasted sweet potato"], ["烤红薯"]),
        "🥐": (["croissant"], ["牛角包", "羊角面包"]),
        "🍞": (["bread"], ["面包"]),
        "🥖": (["baguette bread", "baguette"], ["法棍"]),
        "🥨": (["pretzel"], ["椒盐卷饼"]),
        "🧀": (["cheese wedge", "cheese"], ["奶酪", "芝士"]),
        "🥚": (["egg"], ["鸡蛋", "蛋"]),
        "🍳": (["cooking", "fried egg"], ["煎蛋"]),
        "🧈": (["butter"], ["黄油"]),
        "🥞": (["pancakes"], ["煎饼", "松饼"]),
        "🧇": (["waffle"], ["华夫饼"]),
        "🥓": (["bacon"], ["培根"]),
        "🍗": (["poultry leg", "chicken leg"], ["鸡腿"]),
        "🍖": (["cut of meat", "meat", "steak"], ["肉", "牛排"]),
        "🌭": (["hot dog"], ["热狗"]),
        "🍔": (["hamburger", "burger"], ["汉堡", "汉堡包"]),
        "🍟": (["french fries", "fries"], ["薯条"]),
        "🍕": (["pizza"], ["披萨", "比萨"]),
        "🥪": (["sandwich"], ["三明治"]),
        "🥙": (["stuffed flatbread", "pita"], ["口袋饼"]),
        "🌮": (["taco"], ["墨西哥卷饼"]),
        "🌯": (["burrito"], ["卷饼"]),
        "🥗": (["green salad", "salad"], ["沙拉", "蔬菜沙拉"]),
        "🥘": (["shallow pan of food", "paella"], ["平底锅菜"]),
        "🍝": (["spaghetti", "pasta"], ["意大利面"]),
        "🍜": (["steaming bowl", "ramen", "noodles"], ["面条", "拉面", "泡面"]),
        "🍲": (["pot of food", "stew", "hot pot"], ["炖菜", "火锅"]),
        "🍛": (["curry rice", "curry"], ["咖喱", "咖喱饭"]),
        "🍣": (["sushi"], ["寿司"]),
        "🍱": (["bento box", "bento"], ["便当"]),
        "🍚": (["cooked rice", "rice"], ["米饭"]),
        "🍥": (["fish cake with swirl"], ["鱼板"]),
        "🥠": (["fortune cookie"], ["签语饼"]),
        "🍦": (["soft ice cream", "ice cream cone"], ["甜筒"]),
        "🍧": (["shaved ice"], ["刨冰"]),
        "🍨": (["ice cream"], ["冰淇淋"]),
        "🍩": (["doughnut", "donut"], ["甜甜圈"]),
        "🍪": (["cookie", "cookies"], ["饼干", "曲奇"]),
        "🎂": (["birthday cake", "birthday"], ["生日蛋糕", "生日"]),
        "🍰": (["shortcake", "cake"], ["蛋糕", "切块蛋糕"]),
        "🧁": (["cupcake"], ["纸杯蛋糕"]),
        "🥧": (["pie"], ["派", "馅饼"]),
        "🍫": (["chocolate bar", "chocolate"], ["巧克力"]),
        "🍬": (["candy"], ["糖果", "糖"]),
        "🍭": (["lollipop"], ["棒棒糖"]),
        "🍯": (["honey pot", "honey"], ["蜂蜜"]),
        "🍼": (["baby bottle"], ["奶瓶"]),
        "🥛": (["glass of milk", "milk"], ["牛奶"]),
        "☕": (["hot beverage", "coffee", "tea"], ["咖啡", "热饮", "茶"]),
        "🍵": (["teacup without handle", "green tea", "matcha"], ["茶杯", "绿茶", "抹茶"]),
        "🧋": (["bubble tea", "boba"], ["奶茶", "珍珠奶茶"]),
        "🧃": (["beverage box", "juice", "juice box"], ["果汁"]),
        "🥤": (["cup with straw", "soda"], ["饮料", "可乐"]),
        "🧉": (["mate"], ["马黛茶"]),
        "🍶": (["sake"], ["清酒"]),
        "🍾": (["bottle with popping cork", "champagne bottle", "champagne"], ["香槟瓶", "开香槟"]),
        "🍷": (["wine glass", "wine", "red wine"], ["红酒", "葡萄酒"]),
        "🍸": (["cocktail glass", "cocktail", "martini"], ["鸡尾酒"]),
        "🍹": (["tropical drink"], ["热带饮品"]),
        "🥂": (["clinking glasses", "champagne glass"], ["碰杯", "举杯"]),
        "🍻": (["clinking beer mugs", "beers", "cheers"], ["干杯", "走一个"]),
        "🍺": (["beer mug", "beer"], ["啤酒"]),
        "🥜": (["peanuts", "peanut"], ["花生"]),
        "🌰": (["chestnut"], ["栗子"]),
        "🍿": (["popcorn"], ["爆米花"]),
        "🥫": (["canned food"], ["罐头"]),
        "🧂": (["salt"], ["盐"]),
        "🥡": (["takeout box"], ["外卖盒", "打包盒"]),
        "🍢": (["oden"], ["关东煮"]),
        "🍡": (["dango"], ["团子"]),
        "🍤": (["fried shrimp", "tempura"], ["炸虾", "天妇罗"]),
        "🍙": (["rice ball", "onigiri"], ["饭团"]),
        "🍘": (["rice cracker"], ["仙贝"]),

        // MARK: Travel and places

        "🚀": (["rocket"], ["火箭", "发射"]),
        "✈️": (["airplane", "plane"], ["飞机", "航班"]),
        "🛫": (["airplane departure"], ["起飞"]),
        "🛬": (["airplane arrival"], ["降落"]),
        "🚗": (["automobile", "car"], ["汽车", "车"]),
        "🚕": (["taxi"], ["出租车", "打车"]),
        "🚙": (["sport utility vehicle", "suv"], ["越野车"]),
        "🚌": (["bus"], ["公交车", "巴士"]),
        "🚎": (["trolleybus"], ["无轨电车"]),
        "🏎️": (["racing car", "race car"], ["赛车"]),
        "🚓": (["police car"], ["警车"]),
        "🚑": (["ambulance"], ["救护车"]),
        "🚒": (["fire engine", "fire truck"], ["消防车"]),
        "🚚": (["delivery truck", "truck"], ["货车", "卡车"]),
        "🚛": (["articulated lorry"], ["大货车"]),
        "🚜": (["tractor"], ["拖拉机"]),
        "🛻": (["pickup truck"], ["皮卡"]),
        "🏍️": (["motorcycle", "motorbike"], ["摩托车"]),
        "🚲": (["bicycle", "bike"], ["自行车", "单车"]),
        "🛴": (["kick scooter", "scooter"], ["滑板车"]),
        "🛹": (["skateboard"], ["滑板"]),
        "🚂": (["steam locomotive"], ["蒸汽火车"]),
        "🚆": (["train"], ["火车"]),
        "🚄": (["high-speed train", "high speed train"], ["高铁"]),
        "🚅": (["bullet train"], ["子弹头列车"]),
        "🚇": (["metro", "subway"], ["地铁"]),
        "🚊": (["tram"], ["有轨电车"]),
        "🚉": (["station"], ["车站"]),
        "🛸": (["flying saucer", "ufo"], ["飞碟", "ufo"]),
        "🚁": (["helicopter"], ["直升机"]),
        "⛵": (["sailboat", "sailing"], ["帆船"]),
        "🚤": (["speedboat"], ["快艇"]),
        "🛳️": (["passenger ship"], ["邮轮"]),
        "⛴️": (["ferry"], ["渡轮"]),
        "🚢": (["ship"], ["轮船"]),
        "⚓": (["anchor"], ["锚"]),
        "⛽": (["fuel pump", "gas"], ["加油站"]),
        "🚧": (["construction"], ["施工中"]),
        "🚦": (["vertical traffic light", "traffic light"], ["红绿灯", "信号灯"]),
        "🗺️": (["world map", "map"], ["地图"]),
        "🧭": (["compass"], ["指南针", "罗盘"]),
        "🗽": (["statue of liberty"], ["自由女神像"]),
        "🗼": (["tokyo tower", "tower"], ["东京塔", "塔"]),
        "🏰": (["castle"], ["城堡"]),
        "🏯": (["japanese castle"], ["日式城堡"]),
        "🏟️": (["stadium"], ["体育场"]),
        "🎡": (["ferris wheel"], ["摩天轮"]),
        "🎢": (["roller coaster"], ["过山车"]),
        "🎠": (["carousel horse"], ["旋转木马"]),
        "⛲": (["fountain"], ["喷泉"]),
        "♨️": (["hot springs"], ["温泉"]),
        "🏭": (["factory"], ["工厂"]),
        "🏢": (["office building", "office"], ["办公楼", "办公室"]),
        "🏬": (["department store"], ["百货商场"]),
        "🏪": (["convenience store", "store"], ["便利店"]),
        "🏫": (["school"], ["学校"]),
        "🏠": (["house", "home"], ["房子", "家"]),
        "🏡": (["house with garden"], ["花园洋房"]),
        "🏥": (["hospital"], ["医院"]),
        "🏦": (["bank"], ["银行"]),
        "🏨": (["hotel"], ["酒店"]),
        "💒": (["wedding"], ["婚礼"]),
        "⛪": (["church"], ["教堂"]),
        "🕌": (["mosque"], ["清真寺"]),
        "⛩️": (["shinto shrine"], ["神社"]),

        // MARK: Objects

        "⌚": (["watch"], ["手表"]),
        "📱": (["mobile phone", "phone", "smartphone", "cellphone"], ["手机"]),
        "📲": (["mobile phone with arrow"], ["来电手机"]),
        "📞": (["telephone receiver", "call"], ["电话", "听筒"]),
        "💻": (["laptop", "computer"], ["笔记本电脑", "电脑"]),
        "⌨️": (["keyboard"], ["键盘"]),
        "🖥️": (["desktop computer", "desktop"], ["台式电脑"]),
        "🖨️": (["printer"], ["打印机"]),
        "🖱️": (["computer mouse"], ["鼠标"]),
        "🕹️": (["joystick"], ["游戏摇杆"]),
        "💾": (["floppy disk", "save"], ["软盘", "保存"]),
        "💿": (["optical disc", "cd"], ["光盘"]),
        "📀": (["dvd"], ["dvd"]),
        "🧮": (["abacus"], ["算盘"]),
        "🎥": (["movie camera"], ["电影摄像机"]),
        "📷": (["camera"], ["相机", "照相机"]),
        "📸": (["camera with flash"], ["闪光相机"]),
        "📹": (["video camera"], ["摄像机"]),
        "📼": (["videocassette"], ["录像带"]),
        "🔍": (["magnifying glass tilted left", "magnifying glass", "search", "zoom"], ["放大镜", "搜索"]),
        "🔎": (["magnifying glass tilted right", "zoom in"], ["查找"]),
        "🕯️": (["candle"], ["蜡烛"]),
        "💡": (["light bulb", "idea", "bulb"], ["灯泡", "想法", "点子"]),
        "🔦": (["flashlight", "torch"], ["手电筒"]),
        "🏮": (["red paper lantern", "lantern"], ["红灯笼", "灯笼"]),
        "📕": (["closed book"], ["合上的书"]),
        "📖": (["open book", "book"], ["书", "翻开的书"]),
        "📚": (["books"], ["书本", "书籍"]),
        "📓": (["notebook"], ["笔记本"]),
        "📜": (["scroll"], ["卷轴"]),
        "📄": (["page facing up", "document"], ["文件", "文档"]),
        "📰": (["newspaper"], ["报纸"]),
        "🔖": (["bookmark"], ["书签"]),
        "🏷️": (["label"], ["标签"]),
        "💰": (["money bag", "money"], ["钱袋", "钱", "发财"]),
        "🪙": (["coin"], ["硬币"]),
        "💴": (["yen banknote", "yen"], ["日元"]),
        "💵": (["dollar banknote", "dollar"], ["美元", "钞票"]),
        "💶": (["euro banknote", "euro"], ["欧元"]),
        "💷": (["pound banknote", "pound"], ["英镑"]),
        "🧾": (["receipt"], ["收据", "账单"]),
        "💳": (["credit card"], ["信用卡"]),
        "💎": (["gem stone", "gem", "diamond"], ["钻石", "宝石"]),
        "⚖️": (["balance scale", "balance"], ["天平", "平衡"]),
        "🪜": (["ladder"], ["梯子"]),
        "🧰": (["toolbox"], ["工具箱"]),
        "🪛": (["screwdriver"], ["螺丝刀"]),
        "🔧": (["wrench"], ["扳手", "工具"]),
        "🔨": (["hammer"], ["锤子", "锤"]),
        "🛠️": (["hammer and wrench", "tools"], ["锤子扳手", "维修"]),
        "⛏️": (["pick"], ["镐"]),
        "🪚": (["saw"], ["锯子"]),
        "🔩": (["nut and bolt"], ["螺栓"]),
        "⚙️": (["gear", "settings"], ["齿轮", "设置"]),
        "🧱": (["brick"], ["砖头"]),
        "⛓️": (["chains"], ["锁链"]),
        "🧲": (["magnet"], ["磁铁"]),
        "🔫": (["water pistol", "pistol"], ["水枪"]),
        "💣": (["bomb"], ["炸弹"]),
        "🧨": (["firecracker"], ["鞭炮", "爆竹"]),
        "🪓": (["axe"], ["斧头"]),
        "🔪": (["kitchen knife", "knife"], ["菜刀", "刀"]),
        "🗡️": (["dagger"], ["匕首"]),
        "⚔️": (["crossed swords"], ["交叉剑"]),
        "🛡️": (["shield"], ["盾牌"]),
        "🚬": (["cigarette"], ["香烟"]),
        "🏺": (["amphora"], ["陶罐"]),
        "🔮": (["crystal ball"], ["水晶球"]),
        "📿": (["prayer beads"], ["念珠"]),
        "🧿": (["nazar amulet"], ["蓝眼睛护身符"]),
        "💈": (["barber pole"], ["理发店转灯"]),
        "🔭": (["telescope"], ["望远镜"]),
        "🔬": (["microscope"], ["显微镜"]),
        "💊": (["pill"], ["药丸", "药"]),
        "💉": (["syringe"], ["注射器", "打针"]),
        "🩸": (["drop of blood"], ["血滴"]),
        "🩹": (["adhesive bandage", "band aid"], ["创可贴"]),
        "🩺": (["stethoscope"], ["听诊器"]),
        "🚪": (["door"], ["门"]),
        "🛋️": (["couch and lamp", "couch"], ["沙发"]),
        "🛏️": (["bed"], ["床"]),
        "🚽": (["toilet"], ["马桶", "厕所"]),
        "🚿": (["shower"], ["淋浴"]),
        "🛁": (["bathtub"], ["浴缸"]),
        "🪥": (["toothbrush"], ["牙刷"]),
        "🧴": (["lotion bottle"], ["乳液瓶"]),
        "🧷": (["safety pin"], ["别针"]),
        "🧹": (["broom"], ["扫帚", "打扫"]),
        "🧺": (["basket"], ["篮子"]),
        "🧻": (["roll of paper"], ["卷纸"]),
        "🪣": (["bucket"], ["水桶"]),
        "🧼": (["soap"], ["肥皂"]),
        "🛎️": (["bellhop bell"], ["服务铃"]),
        "🔑": (["key"], ["钥匙", "密钥"]),
        "🗝️": (["old key"], ["旧钥匙"]),
        "🪑": (["chair"], ["椅子"]),
        "🛗": (["elevator"], ["电梯"]),
        "🧸": (["teddy bear", "teddy"], ["泰迪熊", "毛绒熊"]),
        "🪩": (["mirror ball"], ["迪斯科球"]),
        "🎈": (["balloon"], ["气球"]),
        "🎉": (["party popper", "tada", "celebrate", "congratulations", "congrats"], ["庆祝", "撒花", "拉炮", "恭喜"]),
        "🎊": (["confetti ball", "confetti"], ["五彩纸屑", "彩带"]),
        "🎐": (["wind chime"], ["风铃"]),
        "🧧": (["red envelope", "red packet"], ["红包"]),
        "🎀": (["bow"], ["蝴蝶结"]),
        "🎁": (["wrapped gift", "gift", "present"], ["礼物", "礼品"]),
        "🏅": (["sports medal"], ["奖牌"]),
        "🏆": (["trophy"], ["奖杯", "冠军"]),
        "🥇": (["1st place medal", "gold medal", "first place", "gold"], ["金牌", "第一名"]),
        "🥈": (["2nd place medal", "silver medal", "second place", "silver"], ["银牌", "第二名"]),
        "🥉": (["3rd place medal", "bronze medal", "third place", "bronze"], ["铜牌", "第三名"]),
        "⚽": (["soccer ball", "soccer"], ["足球"]),
        "🏀": (["basketball"], ["篮球"]),
        "🏈": (["american football", "football"], ["橄榄球"]),
        "⚾": (["baseball"], ["棒球"]),
        "🥎": (["softball"], ["垒球"]),
        "🎾": (["tennis"], ["网球"]),
        "🏐": (["volleyball"], ["排球"]),
        "🏉": (["rugby football", "rugby"], ["英式橄榄球"]),
        "🥏": (["flying disc", "frisbee"], ["飞盘"]),
        "🎱": (["pool 8 ball", "8 ball", "billiards"], ["台球", "桌球"]),
        "🏓": (["ping pong", "table tennis"], ["乒乓球"]),
        "🏸": (["badminton"], ["羽毛球"]),
        "🥊": (["boxing glove"], ["拳击手套"]),
        "🥋": (["martial arts uniform"], ["道服", "武术"]),
        "🥅": (["goal net"], ["球门"]),
        "⛳": (["flag in hole", "golf"], ["高尔夫", "进洞"]),
        "⛸️": (["ice skate"], ["冰鞋", "滑冰"]),
        "🎣": (["fishing pole", "fishing"], ["钓鱼"]),
        "🤿": (["diving mask"], ["潜水镜"]),
        "🎽": (["running shirt"], ["运动衫"]),
        "🎿": (["skis", "ski"], ["滑雪板", "滑雪"]),
        "🛷": (["sled"], ["雪橇"]),
        "🥌": (["curling stone"], ["冰壶"]),
        "🎯": (["bullseye", "dart", "target", "dart board"], ["靶心", "目标", "飞镖"]),
        "🪀": (["yo-yo"], ["悠悠球"]),
        "🪁": (["kite"], ["风筝"]),
        "🎮": (["video game", "gaming", "gamepad", "game controller"], ["游戏手柄", "游戏"]),
        "🎲": (["game die", "dice", "die"], ["骰子", "色子"]),
        "🧩": (["puzzle piece", "puzzle"], ["拼图"]),
        "♟️": (["chess pawn", "chess"], ["国际象棋"]),
        "🎰": (["slot machine"], ["老虎机"]),
        "🎳": (["bowling"], ["保龄球"]),

        // MARK: Music, media and signs

        "🎭": (["performing arts"], ["戏剧"]),
        "🎨": (["artist palette", "art", "palette"], ["调色板", "艺术", "画画"]),
        "🎬": (["clapper board", "movie"], ["场记板", "电影"]),
        "🎤": (["microphone", "mic"], ["麦克风", "话筒"]),
        "🎧": (["headphone", "headphones"], ["耳机"]),
        "🎼": (["musical score"], ["乐谱"]),
        "🎵": (["musical note", "music note", "music"], ["音符", "音乐"]),
        "🎶": (["musical notes", "music notes", "songs"], ["多个音符", "歌曲"]),
        "🎹": (["musical keyboard", "piano"], ["钢琴"]),
        "🥁": (["drum"], ["鼓"]),
        "🎷": (["saxophone"], ["萨克斯"]),
        "🎺": (["trumpet"], ["小号"]),
        "🎸": (["guitar"], ["吉他"]),
        "🪕": (["banjo"], ["班卓琴"]),
        "🎻": (["violin"], ["小提琴"]),
        "📻": (["radio"], ["收音机", "电台"]),
        "📺": (["television", "tv"], ["电视"]),
        "🔔": (["bell"], ["铃铛", "响铃"]),
        "🔕": (["bell with slash"], ["静音铃"]),
        "📢": (["loudspeaker", "announcement"], ["大喇叭", "公告"]),
        "📣": (["megaphone", "cheering megaphone"], ["扩音器"]),
        "🫧": (["bubbles"], ["泡泡"]),
        "🎄": (["christmas tree"], ["圣诞树"]),
        "🎆": (["fireworks"], ["烟花", "焰火"]),
        "🎇": (["sparkler"], ["仙女棒"]),

        // MARK: Signs and arrows

        "✅": (["check mark button", "green check", "done"], ["对勾", "勾", "完成"]),
        "☑️": (["check box with check", "checked box"], ["勾选框"]),
        "✔️": (["check mark", "check"], ["对号", "勾选"]),
        "❌": (["cross mark", "x mark", "wrong"], ["错", "叉", "错误"]),
        "❎": (["cross mark button"], ["取消按钮"]),
        "❗": (["exclamation mark", "exclamation"], ["感叹号"]),
        "❕": (["white exclamation mark"], ["白色感叹号"]),
        "❓": (["question mark", "question"], ["问号", "疑问"]),
        "❔": (["white question mark"], ["白色问号"]),
        "⁉️": (["exclamation question mark"], ["感叹问号"]),
        "‼️": (["double exclamation mark"], ["双感叹号"]),
        "⚠️": (["warning", "caution"], ["警告", "当心"]),
        "🔞": (["no one under eighteen"], ["未成年人禁止"]),
        "🚫": (["prohibited", "forbidden", "not allowed"], ["禁止", "不允许"]),
        "🚭": (["no smoking"], ["禁止吸烟"]),
        "♻️": (["recycling symbol", "recycle", "recycling"], ["回收"]),
        "⚜️": (["fleur-de-lis", "fleur de lis"], ["鸢尾花纹章"]),
        "🔱": (["trident emblem", "trident"], ["三叉戟"]),
        "📛": (["name badge"], ["名牌"]),
        "🔰": (["japanese beginner symbol"], ["新手标记"]),
        "✳️": (["eight-spoked asterisk", "asterisk"], ["米字星号"]),
        "❇️": (["sparkle"], ["闪亮星点"]),
        "✴️": (["eight-pointed star"], ["八角星"]),
        "➕": (["plus", "plus sign", "add"], ["加号", "添加"]),
        "➖": (["minus", "minus sign", "subtract"], ["减号"]),
        "➗": (["divide", "division sign"], ["除号"]),
        "✖️": (["multiply", "multiplication sign", "times"], ["乘号"]),
        "🟰": (["equals sign", "equals"], ["等号"]),
        "♾️": (["infinity"], ["无穷大", "无限"]),
        "💲": (["heavy dollar sign"], ["美元符号"]),
        "💱": (["currency exchange"], ["货币兑换"]),
        "©️": (["copyright"], ["版权"]),
        "®️": (["registered"], ["注册商标"]),
        "™️": (["trademark", "tm"], ["商标"]),
        "🔴": (["red circle", "red dot"], ["红点", "红圈"]),
        "🟠": (["orange circle", "orange dot"], ["橙点"]),
        "🟡": (["yellow circle", "yellow dot"], ["黄点"]),
        "🟢": (["green circle", "green dot"], ["绿点"]),
        "🔵": (["blue circle", "blue dot"], ["蓝点"]),
        "🟣": (["purple circle", "purple dot"], ["紫点"]),
        "🟤": (["brown circle", "brown dot"], ["棕点"]),
        "⚫": (["black circle", "black dot"], ["黑点"]),
        "⚪": (["white circle", "white dot"], ["白点"]),
        "🟥": (["red square"], ["红色方块"]),
        "🟧": (["orange square"], ["橙色方块"]),
        "🟨": (["yellow square"], ["黄色方块"]),
        "🟩": (["green square"], ["绿色方块"]),
        "🟦": (["blue square"], ["蓝色方块"]),
        "⬛": (["black large square"], ["黑色方块"]),
        "⬜": (["white large square"], ["白色方块"]),
        "🔶": (["large orange diamond"], ["橙色菱形"]),
        "🔷": (["large blue diamond"], ["蓝色菱形"]),
        "🔺": (["red triangle pointed up", "red triangle"], ["红色三角"]),
        "🔻": (["red triangle pointed down"], ["倒三角"]),
        "⬆️": (["up arrow"], ["向上箭头"]),
        "↗️": (["up-right arrow", "up right arrow"], ["右上箭头"]),
        "➡️": (["right arrow"], ["向右箭头"]),
        "↘️": (["down-right arrow"], ["右下箭头"]),
        "⬇️": (["down arrow"], ["向下箭头"]),
        "↙️": (["down-left arrow"], ["左下箭头"]),
        "⬅️": (["left arrow"], ["向左箭头"]),
        "↖️": (["up-left arrow"], ["左上箭头"]),
        "↕️": (["up-down arrow"], ["上下箭头"]),
        "↔️": (["left-right arrow"], ["左右箭头"]),
        "↪️": (["right arrow curving left"], ["右弯箭头"]),
        "↩️": (["left arrow curving right"], ["左弯箭头"]),
        "⤴️": (["right arrow curving up"], ["上弯箭头"]),
        "⤵️": (["right arrow curving down"], ["下弯箭头"]),
        "🔃": (["clockwise vertical arrows"], ["顺时针箭头"]),
        "🔄": (["counterclockwise arrows", "refresh", "sync"], ["刷新", "同步"]),
        "🔁": (["repeat button", "repeat", "loop"], ["循环", "重复"]),
        "🔂": (["repeat single button"], ["单曲循环"]),
        "▶️": (["play button", "play"], ["播放", "播放键"]),
        "⏩": (["fast-forward button", "fast forward"], ["快进"]),
        "⏭️": (["next track button", "next track"], ["下一首"]),
        "⏯️": (["play or pause button"], ["播放暂停"]),
        "◀️": (["reverse button", "reverse"], ["倒带"]),
        "⏪": (["fast reverse button", "fast reverse"], ["快退"]),
        "⏮️": (["last track button", "last track"], ["上一首"]),
        "🔼": (["up button"], ["上三角按钮"]),
        "⏫": (["fast up button"], ["快速向上"]),
        "🔽": (["down button"], ["下三角按钮"]),
        "⏬": (["fast down button"], ["快速向下"]),
        "⏸️": (["pause button", "pause"], ["暂停"]),
        "⏹️": (["stop button", "stop"], ["停止"]),
        "⏺️": (["record button", "record"], ["录制"]),
        "⏏️": (["eject button", "eject"], ["弹出"]),
        "🔀": (["shuffle tracks button", "shuffle"], ["随机播放"]),
        "🔉": (["speaker medium volume", "volume"], ["音量"]),
        "🔈": (["speaker low volume"], ["低音量"]),
        "🔇": (["muted speaker", "mute"], ["静音"]),
        "🔊": (["speaker high volume"], ["高音量"]),
        "🔋": (["battery"], ["电池"]),
        "🪫": (["low battery"], ["低电量"]),
        "🔌": (["electric plug"], ["插头"]),

        // MARK: Time and office

        "⏰": (["alarm clock", "clock", "alarm"], ["闹钟"]),
        "⏱️": (["stopwatch"], ["秒表"]),
        "⏲️": (["timer clock", "timer"], ["计时器"]),
        "🕰️": (["mantelpiece clock"], ["座钟"]),
        "⌛": (["hourglass"], ["沙漏"]),
        "⏳": (["hourglass done", "hourglass with sand"], ["时间快到", "倒计时"]),
        "📅": (["calendar"], ["日历", "日期"]),
        "📆": (["tear-off calendar"], ["撕页日历"]),
        "🗓️": (["spiral calendar"], ["螺旋日历"]),
        "📇": (["card index"], ["名片盒"]),
        "📈": (["chart increasing", "up chart"], ["涨图", "上升"]),
        "📉": (["chart decreasing", "down chart"], ["跌图", "下降"]),
        "📊": (["bar chart"], ["柱状图", "统计"]),
        "📋": (["clipboard"], ["剪贴板"]),
        "📌": (["pushpin", "pin"], ["图钉", "置顶"]),
        "📍": (["round pushpin", "location pin", "location", "gps"], ["定位", "位置"]),
        "📎": (["paperclip", "attachment"], ["回形针", "附件"]),
        "🖇️": (["linked paperclips"], ["连环回形针"]),
        "📏": (["straight ruler", "ruler"], ["直尺", "尺子"]),
        "📐": (["triangular ruler"], ["三角尺"]),
        "✂️": (["scissors", "cut"], ["剪刀", "剪断"]),
        "🗃️": (["card file box"], ["档案盒"]),
        "🗄️": (["file cabinet"], ["文件柜"]),
        "🗑️": (["wastebasket", "trash"], ["垃圾桶"]),
        "🔒": (["locked", "lock"], ["锁定", "锁"]),
        "🔓": (["unlocked", "unlock"], ["解锁"]),
        "🔐": (["locked with key"], ["带钥匙锁"]),
        "🔏": (["locked with pen"], ["带笔锁"]),
        "🔗": (["link"], ["链接"]),
        "🖋️": (["fountain pen"], ["钢笔"]),
        "🖊️": (["pen"], ["笔"]),
        "🖌️": (["paintbrush"], ["画笔"]),
        "🖍️": (["crayon"], ["蜡笔"]),
        "📝": (["memo", "note"], ["备忘录", "笔记"]),
        "✏️": (["pencil"], ["铅笔"]),
        "💼": (["briefcase"], ["公文包"]),
        "📁": (["file folder", "folder"], ["文件夹"]),
        "📂": (["open file folder"], ["打开的文件夹"]),
        "🗂️": (["card index dividers"], ["分隔文件夹"]),
        "📧": (["e-mail", "email", "mail"], ["电子邮件", "邮件"]),
        "✉️": (["envelope"], ["信封"]),
        "📨": (["incoming envelope"], ["来信"]),
        "📩": (["envelope with arrow"], ["发送邮件"]),
        "📤": (["outbox tray"], ["发件箱"]),
        "📥": (["inbox tray"], ["收件箱"]),
        "📦": (["package"], ["包裹", "快递"]),
        "📫": (["closed mailbox with raised flag", "mailbox"], ["邮箱"]),
        "📮": (["postbox"], ["邮筒"]),
        "🗳️": (["ballot box with ballot"], ["投票箱"]),
        "🛒": (["shopping cart", "cart"], ["购物车"]),
        "🎫": (["ticket"], ["门票", "票"]),

        // MARK: Clothing and accessories

        "👓": (["glasses", "eyeglasses"], ["眼镜"]),
        "🕶️": (["sunglasses"], ["墨镜", "太阳镜"]),
        "🥽": (["goggles"], ["护目镜"]),
        "🥼": (["lab coat"], ["白大褂"]),
        "🦺": (["safety vest"], ["安全背心"]),
        "👔": (["necktie", "tie"], ["领带"]),
        "👕": (["t-shirt", "tshirt", "shirt"], ["t恤", "衣服"]),
        "👖": (["jeans"], ["牛仔裤"]),
        "🧣": (["scarf"], ["围巾"]),
        "🧤": (["gloves"], ["手套"]),
        "🧥": (["coat"], ["外套", "大衣"]),
        "🧦": (["socks"], ["袜子"]),
        "👗": (["dress"], ["连衣裙", "裙子"]),
        "👘": (["kimono"], ["和服"]),
        "🥻": (["sari"], ["纱丽"]),
        "🩱": (["one-piece swimsuit"], ["连体泳衣"]),
        "🩲": (["briefs"], ["三角泳裤"]),
        "🩳": (["shorts"], ["短裤"]),
        "👙": (["bikini"], ["比基尼"]),
        "👚": (["woman's clothes"], ["女装"]),
        "👛": (["purse"], ["钱包"]),
        "👜": (["handbag"], ["手提包"]),
        "👝": (["clutch bag"], ["手拿包"]),
        "🛍️": (["shopping bags", "shopping"], ["购物袋", "购物"]),
        "🎒": (["backpack"], ["背包", "书包"]),
        "👞": (["man's shoe"], ["男鞋"]),
        "👟": (["running shoe", "sneaker"], ["运动鞋", "跑鞋"]),
        "🥾": (["hiking boot"], ["登山鞋"]),
        "🥿": (["flat shoe"], ["平底鞋"]),
        "👠": (["high-heeled shoe", "high heel"], ["高跟鞋"]),
        "👡": (["woman's sandal"], ["凉鞋"]),
        "🩴": (["thong sandal", "flip flop"], ["人字拖"]),
        "👢": (["woman's boot"], ["女靴"]),
        "👑": (["crown"], ["王冠", "皇冠"]),
        "👒": (["woman's hat"], ["遮阳帽"]),
        "🎩": (["top hat"], ["礼帽"]),
        "🎓": (["graduation cap", "graduation"], ["学位帽", "毕业"]),
        "🧢": (["billed cap", "cap", "hat"], ["帽子", "鸭舌帽"]),
        "🪖": (["military helmet"], ["军用头盔"]),
        "⛑️": (["rescue worker's helmet"], ["救援头盔"]),
        "💄": (["lipstick"], ["口红"]),
        "💍": (["ring"], ["戒指"]),
        "💋": (["kiss mark", "lipstick kiss", "lip print"], ["唇印"]),
        "🩰": (["ballet shoes"], ["芭蕾舞鞋"]),

        // MARK: People

        "👶": (["baby"], ["婴儿", "宝宝"]),
        "🧒": (["child"], ["儿童"]),
        "🧑": (["person"], ["人"]),
        "👩": (["woman"], ["女人"]),
        "🧑‍💻": (["technologist", "programmer"], ["程序员", "码农"]),
        "🧑‍🔬": (["scientist"], ["科学家"]),
        "🧑‍🎨": (["artist"], ["画家", "艺术家"]),
        "🧑‍🍳": (["cook", "chef"], ["厨师"]),
        "🧑‍⚕️": (["health worker", "doctor", "nurse"], ["医生", "护士"]),
        "🧑‍🏫": (["teacher"], ["老师"]),
        "🧑‍⚖️": (["judge"], ["法官"]),
        "🧑‍✈️": (["pilot"], ["飞行员", "机长"]),
        "🧑‍🚀": (["astronaut"], ["宇航员"]),
        "🧑‍🌾": (["farmer"], ["农民", "农夫"]),
        "👮": (["police officer", "police"], ["警察"]),
        "🕵️": (["detective", "sleuth"], ["侦探"]),
        "💂": (["guard"], ["卫兵"]),
        "👷": (["construction worker"], ["工人", "建筑工人"]),
        "🤴": (["prince"], ["王子"]),
        "👸": (["princess"], ["公主"]),
        "🤵": (["person in tuxedo", "groom"], ["新郎"]),
        "👰": (["person with veil", "bride"], ["新娘"]),
        "🤰": (["pregnant woman"], ["孕妇"]),
        "🤱": (["breast-feeding"], ["哺乳"]),
        "👼": (["baby angel"], ["小天使"]),
    ]

    private static let lookup: [String: String] = {
        var table: [String: String] = [:]
        for (emoji, names) in entries {
            for name in names.english + names.chinese where !name.isEmpty {
                table[normalizedKey(name)] = emoji
            }
        }
        return table
    }()

    /// Space-free variants of every multi-word name so `:thumbsup:` and
    /// `red-heart` resolve like their spaced forms.
    private static let compactLookup: [String: String] = {
        var table: [String: String] = [:]
        for (key, emoji) in lookup where key.contains(" ") {
            table[key.replacingOccurrences(of: " ", with: "")] = emoji
        }
        return table
    }()

    private static let supplementalCatalogs = SupplementalCatalogCache()
    private static let maximumCandidateCount = 6

    /// Resolves a copied value to the emoji it names, or `nil` when the value
    /// is not a known emoji name.
    public static func emoji(
        for name: String,
        language: AppLanguage = AppLocalization.currentLanguage
    ) -> String? {
        emojiCandidates(for: name, language: language).first
    }

    /// Returns the most relevant Emoji candidates for a copied name. Exact
    /// curated aliases remain deterministic; CLDR aliases can add nearby
    /// candidates for a concise natural-language description.
    static func emojiCandidates(
        for name: String,
        language: AppLanguage = AppLocalization.currentLanguage
    ) -> [String] {
        let key = normalizedKey(name)
        guard !key.isEmpty, key.count <= 64 else { return [] }
        if let emoji = lookup[key] { return [emoji] }
        let compact = key.replacingOccurrences(of: " ", with: "")
        if let emoji = compactLookup[compact] { return [emoji] }

        let catalogs = lookupLanguages(for: key, preferred: language).compactMap {
            supplementalCatalogs.catalog(for: $0)
        }
        guard !catalogs.isEmpty else { return [] }

        let exact = unique(catalogs.flatMap {
            isExplicitShortcode(name)
                ? $0.shortcodeCandidates(for: key, compact: compact)
                : $0.canonicalCandidates(for: key, compact: compact)
        })
        guard let query = EmojiQuery(key: key),
              query.allowsFuzzyMatching,
              !looksLikeSentence(key)
        else {
            return Array(exact.prefix(maximumCandidateCount))
        }

        let fuzzy = rankedFuzzyCandidates(
            for: query,
            catalogs: catalogs,
            excluding: Set(exact)
        )
        return Array(unique(exact + fuzzy).prefix(maximumCandidateCount))
    }

    /// Maps an explicit formatter locale back to the app's supported language
    /// set, so detector tests and live settings use the same catalog slice.
    static func language(for locale: Locale) -> AppLanguage {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if identifier.hasPrefix("zh-Hant") || identifier.hasPrefix("zh-TW") || identifier.hasPrefix("zh-HK") {
            return .traditionalChinese
        }
        if identifier.hasPrefix("zh") {
            return .simplifiedChinese
        }
        if let exact = AppLanguage(rawValue: identifier) {
            return exact
        }
        let primary = identifier.split(separator: "-").first.map(String.init)
        return primary.flatMap { code in
            AppLanguage.allCases.first {
                $0.rawValue.caseInsensitiveCompare(code) == .orderedSame
            }
        } ?? AppLocalization.currentLanguage
    }

    static func supplementalEmojiCount(for language: AppLanguage) -> Int? {
        supplementalCatalogs.catalog(for: language)?.emojiCount
    }

    static func supplementalSampleAlias(for language: AppLanguage) -> (emoji: String, alias: String)? {
        supplementalCatalogs.catalog(for: language)?.sampleAlias
    }

    private static func lookupLanguages(for query: String, preferred: AppLanguage) -> [AppLanguage] {
        var languages = [preferred]
        if let detected = detectedLanguage(for: query) {
            languages.append(detected)
        }
        languages += [.english, .simplifiedChinese, .traditionalChinese]
        var seen: Set<AppLanguage> = []
        return languages.filter { seen.insert($0).inserted }
    }

    private static func detectedLanguage(for text: String) -> AppLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let rawValue = recognizer.dominantLanguage?.rawValue else { return nil }
        switch rawValue.lowercased() {
        case "zh-hans", "zh-cn", "zh": return .simplifiedChinese
        case "zh-hant", "zh-tw", "zh-hk": return .traditionalChinese
        case "pt": return .brazilianPortuguese
        default:
            return AppLanguage.allCases.first {
                $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame
            }
        }
    }

    private static func rankedFuzzyCandidates(
        for query: EmojiQuery,
        catalogs: [SupplementalCatalog],
        excluding exact: Set<String>
    ) -> [String] {
        var scores: [String: Double] = [:]
        for catalog in catalogs {
            for candidate in catalog.fuzzyCandidates(for: query) where !exact.contains(candidate.emoji) {
                scores[candidate.emoji] = max(scores[candidate.emoji] ?? 0, candidate.score)
            }
        }
        return scores
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .map(\.key)
    }

    private static func looksLikeSentence(_ value: String) -> Bool {
        guard !value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) else {
            return true
        }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = value
        var firstTag: NLTag?
        var tags: [NLTag] = []
        var wordCount = 0
        tagger.enumerateTags(
            in: value.startIndex..<value.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, _ in
            if firstTag == nil {
                firstTag = tag
            }
            if let tag {
                tags.append(tag)
            }
            wordCount += 1
            return true
        }
        guard wordCount > 1 else { return false }
        if !tags.isEmpty && tags.allSatisfy({ $0 == .number }) {
            return true
        }
        if firstTag == .pronoun || firstTag == .determiner || firstTag == .interjection {
            return true
        }
        return firstTag == .verb && tags.dropFirst().contains {
            $0 == .determiner || $0 == .preposition || $0 == .pronoun
        }
    }

    private static func isExplicitShortcode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 2 && trimmed.hasPrefix(":") && trimmed.hasSuffix(":")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func fuzzyScore(query: EmojiQuery, alias: AliasRecord) -> Double? {
        let sharedGrams = query.grams.intersection(alias.grams).count
        guard sharedGrams > 0 else { return nil }

        let editDistance = levenshteinDistance(query.characters, alias.characters)
        let longestLength = max(query.characters.count, alias.characters.count)
        let editSimilarity = 1 - Double(editDistance) / Double(longestLength)
        let diceSimilarity = Double(2 * sharedGrams) / Double(query.grams.count + alias.grams.count)
        let suffixSimilarity = Double(commonSuffixLength(query.characters, alias.characters))
            / Double(query.characters.count)
        let substringSimilarity = Double(longestCommonSubstringLength(query.characters, alias.characters))
            / Double(min(query.characters.count, alias.characters.count))
        let sharedWords = query.words.intersection(alias.words).count
        let wordSimilarity = query.words.isEmpty || alias.words.isEmpty
            ? 0
            : Double(2 * sharedWords) / Double(query.words.count + alias.words.count)
        let score = editSimilarity * 0.55
            + diceSimilarity * 0.20
            + suffixSimilarity * 0.30
            + wordSimilarity * 0.15
            + substringSimilarity * 0.25
        return score >= 0.52 ? score : nil
    }

    private static func contentWords(in value: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = value
        var words: Set<String> = []
        tagger.enumerateTags(
            in: value.startIndex..<value.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard let tag else { return true }
            switch tag {
            case .pronoun, .determiner, .preposition, .conjunction, .particle:
                return true
            default:
                words.insert(String(value[range]).lowercased())
                return true
            }
        }
        return words
    }

    private static func levenshteinDistance(_ left: [Character], _ right: [Character]) -> Int {
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func commonSuffixLength(_ left: [Character], _ right: [Character]) -> Int {
        var count = 0
        for (leftCharacter, rightCharacter) in zip(left.reversed(), right.reversed()) {
            guard leftCharacter == rightCharacter else { break }
            count += 1
        }
        return count
    }

    private static func longestCommonSubstringLength(_ left: [Character], _ right: [Character]) -> Int {
        var previous = Array(repeating: 0, count: right.count + 1)
        var longest = 0
        for leftCharacter in left {
            var current = Array(repeating: 0, count: right.count + 1)
            for (rightIndex, rightCharacter) in right.enumerated() {
                if leftCharacter == rightCharacter {
                    current[rightIndex + 1] = previous[rightIndex] + 1
                    longest = max(longest, current[rightIndex + 1])
                }
            }
            previous = current
        }
        return longest
    }

    private static func characterNgrams(_ characters: [Character]) -> Set<String> {
        guard characters.count >= 2 else { return [] }
        let length = characters.count >= 3 ? 3 : 2
        return Set((0...(characters.count - length)).map { offset in
            String(characters[offset..<(offset + length)])
        })
    }

    private struct EmojiQuery {
        let characters: [Character]
        let grams: Set<String>
        let words: Set<String>

        init?(key: String) {
            let compact = key.replacingOccurrences(of: " ", with: "")
            let characters = Array(compact)
            guard characters.count >= 2 else { return nil }
            self.characters = characters
            grams = EmojiNameCatalog.characterNgrams(characters)
            words = EmojiNameCatalog.contentWords(in: key)
        }

        var allowsFuzzyMatching: Bool {
            characters.count >= 3 && !grams.isEmpty && words.count > 1
        }
    }

    private struct AliasRecord {
        let emoji: String
        let characters: [Character]
        let grams: Set<String>
        let words: Set<String>

        init(emoji: String, key: String) {
            self.emoji = emoji
            characters = Array(key.replacingOccurrences(of: " ", with: ""))
            grams = EmojiNameCatalog.characterNgrams(characters)
            words = EmojiNameCatalog.contentWords(in: key)
        }
    }

    private struct FuzzyCandidate {
        let emoji: String
        let score: Double
    }

    private struct SupplementalCatalog {
        let canonicalExact: [String: [String]]
        let canonicalCompact: [String: [String]]
        let shortcodeExact: [String: [String]]
        let shortcodeCompact: [String: [String]]
        let fuzzyNames: [AliasRecord]
        let emojiCount: Int
        let sampleAlias: (emoji: String, alias: String)?

        init(
            primaryAliases: [String: [String]],
            fallbackAliases: [String: [String]],
            primaryCanonicalNames: [String: [String]],
            fallbackCanonicalNames: [String: [String]]
        ) {
            var canonicalExact: [String: [String]] = [:]
            var canonicalCompact: [String: [String]] = [:]
            var shortcodeExact: [String: [String]] = [:]
            var shortcodeCompact: [String: [String]] = [:]
            var fuzzyNames: [AliasRecord] = []
            var seenRecords: Set<String> = []

            for aliasesByEmoji in [primaryAliases, fallbackAliases] {
                for emoji in aliasesByEmoji.keys.sorted() {
                    for alias in aliasesByEmoji[emoji] ?? [] {
                        let key = EmojiNameCatalog.normalizedKey(alias)
                        guard !key.isEmpty else { continue }
                        Self.append(emoji, to: &shortcodeExact, for: key)
                        let compactKey = key.replacingOccurrences(of: " ", with: "")
                        if compactKey != key {
                            Self.append(emoji, to: &shortcodeCompact, for: compactKey)
                        }
                    }
                }
            }

            for namesByEmoji in [primaryCanonicalNames, fallbackCanonicalNames] {
                for emoji in namesByEmoji.keys.sorted() {
                    for name in namesByEmoji[emoji] ?? [] {
                        let key = EmojiNameCatalog.normalizedKey(name)
                        guard !key.isEmpty else { continue }
                        Self.append(emoji, to: &canonicalExact, for: key)
                        let compactKey = key.replacingOccurrences(of: " ", with: "")
                        if compactKey != key {
                            Self.append(emoji, to: &canonicalCompact, for: compactKey)
                        }
                        let recordKey = emoji + "\u{0}" + key
                        if seenRecords.insert(recordKey).inserted {
                            fuzzyNames.append(AliasRecord(emoji: emoji, key: key))
                        }
                    }
                }
            }

            self.canonicalExact = canonicalExact
            self.canonicalCompact = canonicalCompact
            self.shortcodeExact = shortcodeExact
            self.shortcodeCompact = shortcodeCompact
            self.fuzzyNames = fuzzyNames
            emojiCount = primaryAliases.count
            sampleAlias = primaryCanonicalNames.keys.sorted().lazy.compactMap { emoji in
                guard EmojiNameCatalog.entries[emoji] == nil else { return nil }
                guard let name = primaryCanonicalNames[emoji]?.first(where: { !$0.isEmpty }) else { return nil }
                let key = EmojiNameCatalog.normalizedKey(name)
                let compactKey = key.replacingOccurrences(of: " ", with: "")
                guard EmojiNameCatalog.lookup[key] == nil,
                      EmojiNameCatalog.compactLookup[compactKey] == nil,
                      canonicalExact[key]?.contains(emoji) == true
                else {
                    return nil
                }
                return (emoji, name)
            }.first
        }

        func canonicalCandidates(for key: String, compact compactKey: String) -> [String] {
            EmojiNameCatalog.unique((canonicalExact[key] ?? []) + (canonicalCompact[compactKey] ?? []))
        }

        func shortcodeCandidates(for key: String, compact compactKey: String) -> [String] {
            EmojiNameCatalog.unique((shortcodeExact[key] ?? []) + (shortcodeCompact[compactKey] ?? []))
        }

        func fuzzyCandidates(for query: EmojiQuery) -> [FuzzyCandidate] {
            var scores: [String: Double] = [:]
            for alias in fuzzyNames {
                guard let score = EmojiNameCatalog.fuzzyScore(query: query, alias: alias) else { continue }
                scores[alias.emoji] = max(scores[alias.emoji] ?? 0, score)
            }
            return scores.map { FuzzyCandidate(emoji: $0.key, score: $0.value) }
        }

        private static func append(_ emoji: String, to table: inout [String: [String]], for key: String) {
            guard !(table[key] ?? []).contains(emoji) else { return }
            table[key, default: []].append(emoji)
        }
    }

    private final class SupplementalCatalogCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [AppLanguage: SupplementalCatalog] = [:]
        private var accessOrder: [AppLanguage] = []

        func catalog(for language: AppLanguage) -> SupplementalCatalog? {
            lock.lock()
            if let existing = values[language] {
                touch(language)
                lock.unlock()
                return existing
            }
            lock.unlock()

            guard let loaded = EmojiNameCatalog.loadSupplementalCatalog(for: language) else { return nil }
            lock.lock()
            defer { lock.unlock() }
            if let existing = values[language] {
                touch(language)
                return existing
            }
            values[language] = loaded
            touch(language)
            while accessOrder.count > 4, let evicted = accessOrder.first {
                accessOrder.removeFirst()
                values.removeValue(forKey: evicted)
            }
            return loaded
        }

        private func touch(_ language: AppLanguage) {
            accessOrder.removeAll { $0 == language }
            accessOrder.append(language)
        }
    }

    private static let supplementalCatalogData: Data? = {
        guard let resourceURL = Bundle.module.url(
            forResource: "EmojiNameAliases",
            withExtension: "json",
            subdirectory: "Emoji"
        ) else {
            return nil
        }
        return try? Data(contentsOf: resourceURL, options: .mappedIfSafe)
    }()

    private static let requestedLanguageKey = CodingUserInfoKey(rawValue: "EmojiNameCatalogLanguage")!

    private static func loadSupplementalCatalog(for language: AppLanguage) -> SupplementalCatalog? {
        guard let data = supplementalCatalogData else { return nil }
        let decoder = JSONDecoder()
        decoder.userInfo[requestedLanguageKey] = language.rawValue
        guard let slice = try? decoder.decode(EmojiCatalogSlice.self, from: data) else { return nil }
        return SupplementalCatalog(
            primaryAliases: slice.primaryAliases,
            fallbackAliases: slice.fallbackAliases,
            primaryCanonicalNames: slice.primaryCanonicalNames,
            fallbackCanonicalNames: slice.fallbackCanonicalNames
        )
    }

    private struct EmojiCatalogSlice: Decodable {
        let primaryAliases: [String: [String]]
        let fallbackAliases: [String: [String]]
        let primaryCanonicalNames: [String: [String]]
        let fallbackCanonicalNames: [String: [String]]

        private enum CodingKeys: String, CodingKey {
            case canonicalNames
            case fallbackLanguage
            case languages
        }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: CodingKeys.self)
            let fallbackLanguage = try root.decode(String.self, forKey: .fallbackLanguage)
            let requestedLanguage = decoder.userInfo[EmojiNameCatalog.requestedLanguageKey] as? String
                ?? fallbackLanguage
            let languages = try root.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .languages)
            let canonicalNames = try root.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .canonicalNames)
            guard let primaryKey = DynamicCodingKey(stringValue: requestedLanguage),
                  let fallbackKey = DynamicCodingKey(stringValue: fallbackLanguage),
                  languages.contains(primaryKey),
                  languages.contains(fallbackKey),
                  canonicalNames.contains(primaryKey),
                  canonicalNames.contains(fallbackKey)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .languages,
                    in: root,
                    debugDescription: "Emoji catalog has no requested language"
                )
            }
            primaryAliases = try languages.decode([String: [String]].self, forKey: primaryKey)
            fallbackAliases = try languages.decode([String: [String]].self, forKey: fallbackKey)
            primaryCanonicalNames = try canonicalNames.decode([String: [String]].self, forKey: primaryKey)
            fallbackCanonicalNames = try canonicalNames.decode([String: [String]].self, forKey: fallbackKey)
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    static func normalizedKey(_ text: String) -> String {
        var key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip `:shortcode:` decoration; a bare or lone colon is kept as-is.
        if key.count > 2, key.hasPrefix(":"), key.hasSuffix(":") {
            key = String(key.dropFirst().dropLast())
        }
        // Slack/GitHub style shortcodes join words with underscores or hyphens.
        key = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return key.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
