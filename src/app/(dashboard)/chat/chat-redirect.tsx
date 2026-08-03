"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/** Client-side navigation into a fresh chat id — avoids server `redirect()`,
 *  which trips a Next.js 16 / Turbopack Performance.measure negative-timestamp
 *  overlay on ChatPage. */
export function ChatRedirect({
  chatId,
  projectId,
}: {
  chatId: string;
  projectId?: string;
}) {
  const router = useRouter();
  useEffect(() => {
    const url = projectId ? `/chat/${chatId}?projectId=${encodeURIComponent(projectId)}` : `/chat/${chatId}`;
    router.replace(url);
  }, [chatId, projectId, router]);

  return (
    <div className="flex min-h-[40vh] items-center justify-center text-sm text-muted-foreground">
      …
    </div>
  );
}
