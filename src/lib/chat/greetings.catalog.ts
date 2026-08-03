import type { Greeting } from "@/lib/chat/greeting";

// The pool of new-chat greetings. The engine (`greeting.ts`) reads the moment
// and picks one that fits — this file is just data and is meant to GROW.
//
// How a line is chosen:
//   - Every condition you set must hold (time/weekdays/months/seasons/weekend).
//     Leave a dimension out and it matches any value of it.
//   - A line with `{name}` is only shown when the user's first name is known;
//     keep a healthy floor of name-less time-of-day lines so there's always
//     something to show.
//   - More specific lines (more conditions) are likelier to win *when their
//     moment comes*, so a Friday-evening line isn't drowned out by generics.
//
// weekday numbers: 0=Sun 1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat.
//
// China-team fork: `zh-CN` + `en` only (no Ukrainian UI strings). Tone: calm,
// office-friendly — no slang, no developer jargon.

export const GREETINGS: Greeting[] = [
  // ── Morning (05–11) ──────────────────────────────────────────────────────
  { id: "morning-1", time: ["morning"], text: { "zh-CN": "早上好！我们从哪里开始？", en: "Good morning! Where do we start?" } },
  { id: "morning-2", time: ["morning"], text: { "zh-CN": "早上好。今天想处理什么？", en: "Morning. What are we working on?" } },
  { id: "morning-3", time: ["morning"], weight: 0.7, text: { "zh-CN": "新的一天。需要我先看哪份材料？", en: "Coffee still warm? Let's get to it" } },
  { id: "morning-name-1", time: ["morning"], text: { "zh-CN": "早上好，{name}。开始工作了吗？", en: "Morning, {name}! Up and at it?" } },
  { id: "morning-name-2", time: ["morning"], text: { "zh-CN": "新的一天。{name} 今天打算做什么？", en: "New day. What's on your plate, {name}?" } },

  // ── Afternoon (12–16) ──────────────────────────────────────────────────────
  { id: "afternoon-1", time: ["afternoon"], text: { "zh-CN": "下午好！需要我帮什么？", en: "Good afternoon! How can I help?" } },
  { id: "afternoon-2", time: ["afternoon"], text: { "zh-CN": "下午了。我们继续哪一项？", en: "Midday mark. Keeping the pace?" } },
  { id: "afternoon-3", time: ["afternoon"], weight: 0.7, text: { "zh-CN": "接下来做什么？", en: "What's next on the list?" } },
  { id: "afternoon-name-1", time: ["afternoon"], text: { "zh-CN": "下午好，{name}。有什么我能帮忙的？", en: "Good to see you, {name}. What's up?" } },
  { id: "afternoon-name-2", time: ["afternoon"], text: { "zh-CN": "下午正忙。{name} 要继续哪件事？", en: "Day's in full swing — carry on, {name}?" } },

  // ── Evening (17–21) ──────────────────────────────────────────────────────
  { id: "evening-1", time: ["evening"], text: { "zh-CN": "晚上好！今天还想处理什么？", en: "Good evening! What are we working on?" } },
  { id: "evening-2", time: ["evening"], text: { "zh-CN": "一天快结束了。要收个尾吗？", en: "Day's winding down. Wrapping up?" } },
  { id: "evening-3", time: ["evening"], weight: 0.7, text: { "zh-CN": "晚上好。需要解决什么问题？", en: "Quiet evening. What are we solving?" } },
  { id: "evening-name-1", time: ["evening"], text: { "zh-CN": "已经晚上了。{name} 还在收尾吗？", en: "Evening already — final touches, {name}?" } },
  { id: "evening-name-2", time: ["evening"], text: { "zh-CN": "晚上好，{name}。需要我帮什么？", en: "Good evening, {name}. How can I help?" } },

  // ── Night (22–04) ─────────────────────────────────────────────────────────
  { id: "night-1", time: ["night"], text: { "zh-CN": "还没休息？我在这里。", en: "Still up? I'm here" } },
  { id: "night-2", time: ["night"], text: { "zh-CN": "加班中？我们继续。", en: "Night shift? Let's go" } },
  { id: "night-3", time: ["night"], weight: 0.6, text: { "zh-CN": "有点晚了。我不着急，慢慢来。", en: "Late hour. I'm in no hurry" } },
  { id: "night-name-1", time: ["night"], text: { "zh-CN": "夜深了，{name} 还在忙。我和你一起。", en: "City's asleep, {name}'s not. I'm with you" } },

  // ── Monday ──────────────────────────────────────────────────────────────
  { id: "monday-1", weekdays: [1], time: ["morning", "afternoon"], weight: 1.3, text: { "zh-CN": "新的一周。我们从哪里开始？", en: "Fresh week. Where do we begin?" } },
  { id: "monday-2", weekdays: [1], time: ["morning"], weight: 1.1, text: { "zh-CN": "周一早上好。轻松开始这一周。", en: "Easy start to the week" } },
  { id: "monday-name", weekdays: [1], time: ["morning", "afternoon"], weight: 1.1, text: { "zh-CN": "周一。{name} 准备好定节奏了吗？", en: "Monday — set the pace, {name}?" } },

  // ── Friday ────────────────────────────────────────────────────────────────
  { id: "friday-1", weekdays: [5], time: ["afternoon", "evening"], weight: 1.4, text: { "zh-CN": "周五了！把剩下的收一收？", en: "It's Friday! Let's wrap things up?" } },
  { id: "friday-2", weekdays: [5], time: ["afternoon"], weight: 1.1, text: { "zh-CN": "一周快结束了。还剩什么？", en: "Home stretch of the week. What's left?" } },
  { id: "friday-eve", weekdays: [5], time: ["evening"], weight: 1.4, text: { "zh-CN": "这一周过去了。可以收工了吗？", en: "Week's behind us. Powering down?" } },

  // ── Weekend ───────────────────────────────────────────────────────────────
  { id: "weekend-1", weekend: true, weight: 1.1, text: { "zh-CN": "周末还在线。需要我帮什么？", en: "Weekend, and here you are. Respect — how can I help?" } },
  { id: "weekend-2", weekend: true, time: ["afternoon", "evening"], text: { "zh-CN": "周末好。接下来安排什么？", en: "Easy weekend. What's on the agenda?" } },
  { id: "weekend-night", weekend: true, time: ["night"], weight: 1.4, text: { "zh-CN": "周末深夜还在忙？", en: "Weekend night and we're working?" } },

  // ── Seasonal ──────────────────────────────────────────────────────────────
  { id: "winter-morning", seasons: ["winter"], time: ["morning"], weight: 1.1, text: { "zh-CN": "冬日早晨。我们开始吧？", en: "Frosty morning. Warm in here — shall we begin?" } },
  { id: "winter-evening", seasons: ["winter"], time: ["evening"], weight: 0.8, text: { "zh-CN": "冬夜适合安静地处理文书。", en: "Winter evening — cosy work time" } },
  { id: "spring", seasons: ["spring"], time: ["morning", "afternoon"], weight: 0.8, text: { "zh-CN": "春天到了。有什么新想法？", en: "Spring outside. Time for fresh ideas" } },
  { id: "summer", seasons: ["summer"], time: ["afternoon", "evening"], weight: 0.8, text: { "zh-CN": "夏日下午。我们接着做？", en: "Summer's calling, work's waiting. Shall we?" } },
  { id: "autumn-evening", seasons: ["autumn"], time: ["evening"], weight: 0.9, text: { "zh-CN": "秋夜安静，适合把事情理清楚。", en: "Autumn evening — perfect for quiet work" } },

  // ── Easter eggs ───────────────────────────────────────────────────────────
  { id: "friday-night", weekdays: [5], time: ["night"], weight: 1.6, text: { "zh-CN": "周五深夜还在加班，真拼。", en: "Friday night, still working. That's a sport now" } },
  { id: "sunday-evening", weekdays: [0], time: ["evening"], weight: 1.4, text: { "zh-CN": "周日晚上。要为下周做点准备吗？", en: "Sunday evening. Spinning up for the week?" } },
  { id: "winter-monday-morning", weekdays: [1], time: ["morning"], seasons: ["winter"], weight: 1.8, text: { "zh-CN": "冬日周一。最难的起床过去了，继续吧。", en: "Winter Monday. The hard part's done — easy from here" } },
  { id: "summer-friday-eve", weekdays: [5], time: ["evening"], seasons: ["summer"], weight: 1.8, text: { "zh-CN": "夏日周五。我们快点收个尾？", en: "Summer Friday, and here you are. Quick wrap-up?" } },
  { id: "deep-night-name", weekdays: [1, 2, 3, 4, 5], time: ["night"], weight: 1.5, text: { "zh-CN": "工作日深夜，{name} 还没停。", en: "Weeknight this late, and {name} won't quit" } },

  // ── Minimal / any-time floor ──────────────────────────────────────────────
  { id: "minimal-1", weight: 0.4, text: { "zh-CN": "我能帮你做什么？", en: "How can I help?" } },
  { id: "minimal-2", weight: 0.4, text: { "zh-CN": "我在听。", en: "I'm listening" } },
  { id: "minimal-3", weight: 0.4, text: { "zh-CN": "要打开哪份文件？", en: "Which document shall we open?" } },
];
