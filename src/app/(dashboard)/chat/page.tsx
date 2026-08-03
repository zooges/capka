import { nanoid } from "nanoid";
import { ChatRedirect } from "./chat-redirect";

// Always create a new chat — sidebar handles navigation to existing chats.
// Use a client replace (not server redirect) to avoid the Next.js 16 Turbopack
// Performance.measure negative-timestamp overlay on aborted RSC redirects.
export default async function ChatPage({
  searchParams,
}: {
  searchParams: Promise<{ projectId?: string }>;
}) {
  const { projectId } = await searchParams;
  return <ChatRedirect chatId={nanoid()} projectId={projectId} />;
}
