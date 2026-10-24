import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging, MulticastMessage } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { onSchedule } from 'firebase-functions/v2/scheduler';

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

/**
 * Tasks use UTC instants in nextFireAt. A one-minute schedule intentionally
 * checks a small late-arrival window; notificationReceipts makes retries safe.
 * Required task fields: ownerId, title, nextFireAt, status, timezone.
 */
export const dispatchDueTaskNotifications = onSchedule(
  { schedule: 'every 1 minutes', timeZone: 'Etc/UTC', region: 'us-central1' },
  async () => {
    const now = Timestamp.now();
    const windowStart = Timestamp.fromMillis(now.toMillis() - 60_000);
    const due = await db.collection('tasks')
      .where('status', '==', 'scheduled')
      .where('nextFireAt', '>', windowStart)
      .where('nextFireAt', '<=', now)
      .get();

    for (const taskDoc of due.docs) {
      const task = taskDoc.data();
      const receiptRef = db.collection('notificationReceipts').doc(`${taskDoc.id}_${(task.nextFireAt as Timestamp).toMillis()}`);
      // Claim before sending to prevent concurrent scheduler invocations from
      // duplicating pushes. A failed send releases the claim for a retry.
      const claimed = await db.runTransaction(async (tx) => {
        const receipt = await tx.get(receiptRef);
        if (receipt.exists) return false;
        tx.create(receiptRef, { taskId: taskDoc.id, ownerId: task.ownerId, state: 'sending', createdAt: now });
        return true;
      });
      if (!claimed) continue;

      try {
        const devices = await db.collection('users').doc(String(task.ownerId))
          .collection('user_devices').where('enabled', '==', true).get();
        const tokens = devices.docs.map((d) => d.get('fcmToken')).filter((v): v is string => typeof v === 'string' && v.length > 0);
        if (tokens.length) {
          const message: MulticastMessage = {
            tokens,
            notification: { title: task.title ?? 'TaskPulse reminder', body: task.body ?? 'A task is due now.' },
            data: {
              taskId: taskDoc.id,
              ownerId: String(task.ownerId),
              actionUrl: typeof task.actionUrl === 'string' ? task.actionUrl : '',
              action: 'task_due',
              scheduledAt: (task.nextFireAt as Timestamp).toDate().toISOString(),
            },
            android: { priority: 'high', notification: { channelId: 'taskpulse_reminders', clickAction: 'FLUTTER_NOTIFICATION_CLICK' } },
          };
          const result = await messaging.sendEachForMulticast(message);
          const invalid = result.responses.flatMap((r, i) => !r.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(r.error?.code ?? '') ? [devices.docs.find((d) => d.get('fcmToken') === tokens[i])?.ref] : []).filter((r): r is NonNullable<typeof r> => !!r);
          if (invalid.length) await db.runTransaction(async (tx) => { invalid.forEach((ref) => tx.update(ref, { enabled: false, tokenInvalidAt: Timestamp.now() })); });
        }
        await receiptRef.update({ state: 'sent', sentAt: Timestamp.now(), deviceCount: tokens.length });
      } catch (error) {
        logger.error('Task notification dispatch failed', { taskId: taskDoc.id, error });
        await receiptRef.delete();
      }
    }
  },
);
