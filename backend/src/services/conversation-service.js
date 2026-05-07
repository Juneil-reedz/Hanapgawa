const { HttpError } = require('../lib/http-error');
const {
  addMessage,
  createConversation,
  findConversationById,
  listConversationsForUser,
  listMessages,
} = require('../repositories/conversation-repository');
const { findUserById } = require('../repositories/user-repository');

async function startConversation({ clientUserId, providerUserId, serviceListingId, bookingId, initialMessage }) {
  const provider = await findUserById(providerUserId);

  if (!provider || !['worker', 'agency'].includes(provider.role)) {
    throw new HttpError(404, 'Provider account not found.');
  }

  return createConversation({ clientUserId, providerUserId, serviceListingId, bookingId, initialMessage });
}

async function getMyConversations(userId) {
  return listConversationsForUser(userId);
}

async function getConversationMessages({ conversationId, auth }) {
  const conversation = await findConversationById(conversationId);

  if (!conversation) {
    throw new HttpError(404, 'Conversation not found.');
  }

  if (![conversation.clientUserId, conversation.providerUserId].includes(auth.sub) && auth.role !== 'admin') {
    throw new HttpError(403, 'You do not have access to this conversation.');
  }

  return {
    conversation,
    messages: await listMessages(conversationId),
  };
}

async function sendConversationMessage({ conversationId, auth, message }) {
  const conversation = await findConversationById(conversationId);

  if (!conversation) {
    throw new HttpError(404, 'Conversation not found.');
  }

  if (![conversation.clientUserId, conversation.providerUserId].includes(auth.sub) && auth.role !== 'admin') {
    throw new HttpError(403, 'You do not have access to this conversation.');
  }

  return addMessage({ conversationId, senderUserId: auth.sub, message });
}

module.exports = {
  getConversationMessages,
  getMyConversations,
  sendConversationMessage,
  startConversation,
};
