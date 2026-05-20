const { HttpError } = require('../lib/http-error');
const {
  addMessage, addSystemMessage, createConversation, deleteConversation, deleteConversationNickname,
  deleteMessage, editMessage, findConversationBetweenUsers, findConversationById,
  getConversationNicknames, listConversationsForUser, listMessages, upsertConversationNickname,
} = require('../repositories/conversation-repository');
const { findUserById } = require('../repositories/user-repository');

async function startConversation({ initiatorUserId, targetUserId, serviceListingId, bookingId, initialMessage }) {
  const target = await findUserById(targetUserId);
  if (!target) throw new HttpError(404, 'User not found.');
  if (initiatorUserId === targetUserId) throw new HttpError(400, 'Cannot message yourself.');

  // Reuse existing conversation between these two users instead of creating a duplicate
  const existing = await findConversationBetweenUsers(initiatorUserId, targetUserId);
  if (existing) {
    const message = await addMessage({
      conversationId: existing.id,
      senderUserId: initiatorUserId,
      message: initialMessage,
    });
    return { conversation: existing, message };
  }

  return createConversation({
    clientUserId: initiatorUserId,
    providerUserId: targetUserId,
    serviceListingId,
    bookingId,
    initialMessage,
  });
}

async function getMyConversations(userId, search = '') {
  return listConversationsForUser(userId, search);
}

async function getConversationMessages({ conversationId, auth }) {
  const conversation = await findConversationById(conversationId);
  if (!conversation) throw new HttpError(404, 'Conversation not found.');
  if (![conversation.clientUserId, conversation.providerUserId].includes(auth.sub) && auth.role !== 'admin')
    throw new HttpError(403, 'You do not have access to this conversation.');
  return { conversation, messages: await listMessages(conversationId) };
}

async function sendConversationMessage({ conversationId, auth, message, image, voiceMessage, voiceDuration, replyToMessageId, forwardedFromMessageId }) {
  const conversation = await findConversationById(conversationId);
  if (!conversation) throw new HttpError(404, 'Conversation not found.');
  if (![conversation.clientUserId, conversation.providerUserId].includes(auth.sub) && auth.role !== 'admin')
    throw new HttpError(403, 'You do not have access to this conversation.');
  return addMessage({ conversationId, senderUserId: auth.sub, message, image, voiceMessage, voiceDuration, replyToMessageId, forwardedFromMessageId });
}

async function deleteConversationMessage({ messageId, auth }) {
  await deleteMessage({ messageId, senderUserId: auth.sub });
}

async function editConversationMessage({ messageId, auth, message }) {
  return editMessage({ messageId, senderUserId: auth.sub, message });
}

async function removeConversation({ conversationId, auth }) {
  await deleteConversation({ conversationId, userId: auth.sub });
}

async function _requireConversationAccess(conversationId, auth) {
  const conversation = await findConversationById(conversationId);
  if (!conversation) throw new HttpError(404, 'Conversation not found.');
  if (![conversation.clientUserId, conversation.providerUserId].includes(auth.sub) && auth.role !== 'admin')
    throw new HttpError(403, 'You do not have access to this conversation.');
  return conversation;
}

async function listNicknames({ conversationId, auth }) {
  await _requireConversationAccess(conversationId, auth);
  return getConversationNicknames(conversationId);
}

async function setNickname({ conversationId, targetUserId, nickname, auth }) {
  const conversation = await _requireConversationAccess(conversationId, auth);
  const target = await findUserById(targetUserId);
  if (!target) throw new HttpError(404, 'Target user not found.');

  const trimmed = (nickname || '').trim();
  if (!trimmed) {
    await deleteConversationNickname(conversationId, targetUserId);
    // System message for clearing
    const setter = await findUserById(auth.sub);
    await addSystemMessage({
      conversationId,
      message: `${setter?.full_name || 'Someone'} cleared ${target.full_name}'s nickname.`,
    });
    return null;
  }

  const result = await upsertConversationNickname(conversationId, targetUserId, trimmed, auth.sub);
  const setter = await findUserById(auth.sub);
  await addSystemMessage({
    conversationId,
    message: `${setter?.full_name || 'Someone'} set ${target.full_name}'s nickname to "${trimmed}".`,
  });
  return result;
}

async function removeNickname({ conversationId, targetUserId, auth }) {
  await _requireConversationAccess(conversationId, auth);
  await deleteConversationNickname(conversationId, targetUserId);
}

module.exports = {
  deleteConversationMessage, editConversationMessage, getConversationMessages,
  getMyConversations, listNicknames, removeConversation, removeNickname,
  sendConversationMessage, setNickname, startConversation,
};
