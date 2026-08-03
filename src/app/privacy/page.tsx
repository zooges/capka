import type { Metadata } from "next";
import type { ReactNode } from "react";
import Link from "next/link";
import { productName, productTagline } from "@/lib/brand";

export const metadata: Metadata = {
  title: `隐私政策 · ${productName()}`,
  description: "邦信阳（B&Y AGENT）移动应用与网页服务隐私政策",
  robots: { index: true, follow: true },
};

const UPDATED = "2026年8月2日";
const OPERATOR = "上海邦信阳律师事务所";
const CONTACT = "privacy@boss-young.com";

/**
 * Public privacy policy for App Store Connect and end users.
 * Kept outside (auth)/(dashboard) so anonymous visitors are not redirected.
 */
export default function PrivacyPage() {
  const brand = productName();
  return (
    <main className="min-h-dvh bg-background px-5 py-10 text-foreground md:px-8 md:py-14">
      <article className="mx-auto max-w-2xl space-y-8 font-sans">
        <header className="space-y-2 border-b border-border/60 pb-6">
          <p className="text-sm text-muted-foreground">{OPERATOR}</p>
          <h1 className="text-2xl font-semibold tracking-tight md:text-3xl">
            {brand} 隐私政策
          </h1>
          <p className="text-sm text-muted-foreground">
            {productTagline()} · 生效 / 更新日期：{UPDATED}
          </p>
        </header>

        <section className="space-y-3 text-[15px] leading-relaxed text-pretty">
          <p>
            本政策说明我们如何在「{brand}」（亦称 B&amp;Y AGENT，含 iOS /
            iPadOS App「邦信阳」及对应网页服务，以下统称「本服务」）中收集、使用与保护个人信息。使用本服务即表示你已阅读并理解本政策。
          </p>
          <p className="text-muted-foreground">
            本服务面向事务所内部同事使用，由{OPERATOR}
            运营；数据在事务所部署或指定的环境中处理。本政策不构成对外公开的法律意见或个案承诺。
          </p>
        </section>

        <Section title="一、我们收集的信息">
          <ul>
            <li>
              <strong>账号信息：</strong>
              姓名、工作邮箱、头像（如通过飞书登录授权提供）、角色与所属组织标识，用于创建与维护登录会话。
            </li>
            <li>
              <strong>你主动提交的内容：</strong>
              对话消息、上传的文件（如 PDF、合同、表格、图片）、语音转写文本、批注与项目说明等，用于完成你交代的任务。
            </li>
            <li>
              <strong>使用与设备信息：</strong>
              登录时间、功能使用记录、错误日志；在你授权通知时，可能使用设备推送令牌以便在任务完成时提醒你。
            </li>
            <li>
              <strong>我们不收集：</strong>
              精确地理位置、通讯录、健康信息，也不将本服务用于跨 App 广告追踪。
            </li>
          </ul>
        </Section>

        <Section title="二、我们如何使用信息">
          <ul>
            <li>提供登录、对话、文件处理、项目与工作区等核心功能；</li>
            <li>在隔离的执行环境中代表你读写与生成文件，并返回结果；</li>
            <li>保障服务安全、排查故障、防止滥用；</li>
            <li>在你允许的情况下发送「任务已完成」等本地或远程通知；</li>
            <li>遵守适用法律或监管要求。</li>
          </ul>
          <p className="mt-3 text-muted-foreground">
            我们不会出售你的个人信息，也不会将其用于与本服务无关的第三方广告。
          </p>
        </Section>

        <Section title="三、存储、共享与跨境">
          <ul>
            <li>
              数据保存在{OPERATOR}
              自建或指定的服务器与存储中，保存期限以实现服务与合规需要为限，并可按所内制度删除或归档。
            </li>
            <li>
              为完成推理或工具调用，内容可能发送至事务所配置的模型或连接器服务提供方；该等传输以实现你发起的任务为目的，并受所内管理与合同约束。
            </li>
            <li>
              除法律要求、保护合法权益或经你另行同意外，我们不会向无关第三方披露你的对话与文件内容。
            </li>
          </ul>
        </Section>

        <Section title="四、你的权利">
          <p>
            你可通过本服务内的账号与设置功能查看或更新部分资料，并可联系管理员申请更正、删除账号相关数据（法律法规另有规定或所内合规留存要求除外）。你可随时在系统设置中关闭通知权限。
          </p>
        </Section>

        <Section title="五、儿童隐私">
          <p>本服务不面向 14 周岁以下儿童。我们不会故意收集儿童的个人信息。</p>
        </Section>

        <Section title="六、政策更新">
          <p>
            我们可能适时更新本政策，并在本页面公布更新日期。重大变更时，将通过合理方式提示。继续使用本服务即视为了解更新后的政策。
          </p>
        </Section>

        <Section title="七、联系我们">
          <p>
            如对本政策或个人信息处理有疑问，请联系：
            <br />
            运营主体：{OPERATOR}
            <br />
            电子邮箱：
            <a className="text-primary underline-offset-2 hover:underline" href={`mailto:${CONTACT}`}>
              {CONTACT}
            </a>
            <br />
            官网：
            <a
              className="text-primary underline-offset-2 hover:underline"
              href="https://www.boss-young.com/"
              rel="noopener noreferrer"
              target="_blank"
            >
              https://www.boss-young.com/
            </a>
          </p>
        </Section>

        <footer className="border-t border-border/60 pt-6 text-sm text-muted-foreground">
          <Link href="/login" className="text-primary underline-offset-2 hover:underline">
            返回登录
          </Link>
        </footer>
      </article>
    </main>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="space-y-3 text-[15px] leading-relaxed text-pretty">
      <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
      <div className="space-y-2 [&_ul]:list-disc [&_ul]:space-y-2 [&_ul]:pl-5 [&_strong]:font-medium">
        {children}
      </div>
    </section>
  );
}
