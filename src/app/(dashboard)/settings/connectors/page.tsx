"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useIsAdmin } from "@/hooks/use-is-admin";

// Connectors merged into Customize. Admins land on the connectors tab; everyone
// else is sent to the skills library so MCP endpoint URLs never appear in Settings.
export default function ConnectorsRedirect() {
  const router = useRouter();
  const isAdmin = useIsAdmin();

  useEffect(() => {
    router.replace(isAdmin ? "/settings/skills?tab=connectors" : "/settings/skills");
  }, [isAdmin, router]);

  return null;
}
