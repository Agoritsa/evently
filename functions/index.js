// code for server side notifications, won't be used after all..blaze plan needed

const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

functions.setGlobalOptions({maxInstances: 10});

exports.sendEventReminders = functions.pubsub.schedule(
    "every 1 hours",
).onRun(async (context) => {
  const now = new Date();
  const in48Hours = new Date(now.getTime() + 48 * 60 * 60 * 1000);

  const favoritesSnapshot = await admin
      .firestore()
      .collection("favorites")
      .get();

  for (const doc of favoritesSnapshot.docs) {
    const data = doc.data();

    if (!data.eventDate || !data.userId || !data.eventName) continue;

    const eventDate = new Date(data.eventDate);

    if (eventDate > now && eventDate <= in48Hours) {
      const userDoc = await admin
          .firestore()
          .collection("users")
          .doc(data.userId)
          .get();

      if (!userDoc.exists) continue;

      const fcmToken = userDoc.data().fcmToken;
      if (!fcmToken) continue;

      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "Upcoming Event Reminder",
          body: `${data.eventName} is happening soon!`,
        },
      });

      console.log(
          `Notification sent to ${data.userId} for event ${data.eventName}`,
      );
    }
  }

  return null;
});
