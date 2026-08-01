import { z } from "zod";
import { apiHandler, requireSession } from "@/lib/auth";
import { db } from "@/lib/db";
import { pushTokens } from "@/lib/db/schema";
import { and, eq } from "drizzle-orm";

const bodySchema = z.object({
  token: z.string().trim().min(32).max(200),
  // Sandbox and production talk to different APNs hosts; the client knows which
  // build it is, the server can't tell from the token.
  environment: z.enum(["sandbox", "production"]).default("production"),
  locale: z.string().max(20).optional(),
});

/**
 * Register this device for finished-turn pushes. Upserts on the token so
 * re-registering (which iOS does on reinstall, restore, and periodically) does
 * not accumulate rows, and re-points a device that changed hands to its new
 * owner rather than leaking the previous user's answers to it.
 */
export const POST = apiHandler(async (req: Request) => {
  const { userId } = await requireSession();
  const body = bodySchema.parse(await req.json());

  await db
    .insert(pushTokens)
    .values({
      token: body.token,
      userId,
      platform: "ios",
      environment: body.environment,
      locale: body.locale ?? null,
    })
    .onConflictDoUpdate({
      target: pushTokens.token,
      set: {
        userId,
        environment: body.environment,
        locale: body.locale ?? null,
        lastSeenAt: new Date(),
      },
    });

  return Response.json({ ok: true });
});

/** Called on sign-out, so a shared device stops receiving the last user's replies. */
export const DELETE = apiHandler(async (req: Request) => {
  const { userId } = await requireSession();
  const token = new URL(req.url).searchParams.get("token");
  if (!token) return Response.json({ error: "token required" }, { status: 400 });
  await db.delete(pushTokens).where(and(eq(pushTokens.token, token), eq(pushTokens.userId, userId)));
  return Response.json({ ok: true });
});
