const { HttpError } = require('../lib/http-error');
const { createBooking } = require('../repositories/booking-repository');
const {
  acceptJobOffer,
  createJobOffer,
  createJobPost,
  findJobOfferById,
  findJobPostById,
  listJobPosts,
  listOffersForJob,
  listOffersForProvider,
} = require('../repositories/job-repository');
const { findUserById } = require('../repositories/user-repository');

async function postJob({ auth, ...payload }) {
  return createJobPost({ clientUserId: auth.sub, ...payload });
}

async function getJobs({ auth, status }) {
  return listJobPosts({ userId: auth.sub, role: auth.role, status });
}

async function getJobDetail({ jobPostId, auth }) {
  const jobPost = await findJobPostById(jobPostId);
  if (!jobPost) {
    throw new HttpError(404, 'Job post not found.');
  }

  const canViewOffers = auth.role === 'admin' || jobPost.clientUserId === auth.sub;
  const offers = canViewOffers
    ? await listOffersForJob(jobPostId)
    : (await listOffersForProvider(auth.sub)).filter((offer) => offer.jobPostId === jobPostId);

  return { jobPost, offers };
}

async function sendOffer({ jobPostId, auth, message, proposedPrice, media }) {
  const provider = await findUserById(auth.sub);
  if (!provider) {
    throw new HttpError(404, 'User not found.');
  }

  const jobPost = await findJobPostById(jobPostId);
  if (!jobPost) {
    throw new HttpError(404, 'Job post not found.');
  }

  if (jobPost.status !== 'open') {
    throw new HttpError(409, 'Offers can only be sent to open jobs.');
  }

  if (jobPost.clientUserId === auth.sub) {
    throw new HttpError(409, 'You cannot send an offer to your own job.');
  }

  return createJobOffer({ jobPostId, providerUserId: auth.sub, message, proposedPrice, media });
}

async function getMyOffers(auth) {
  return listOffersForProvider(auth.sub);
}

async function chooseOffer({ jobPostId, offerId, auth }) {
  const jobPost = await findJobPostById(jobPostId);
  if (!jobPost) {
    throw new HttpError(404, 'Job post not found.');
  }

  if (jobPost.clientUserId !== auth.sub && auth.role !== 'admin') {
    throw new HttpError(403, 'Only the job owner can accept an offer.');
  }

  if (jobPost.status !== 'open') {
    throw new HttpError(409, 'This job is no longer open.');
  }

  const existingOffer = await findJobOfferById(offerId);
  if (!existingOffer || existingOffer.jobPostId !== jobPostId) {
    throw new HttpError(404, 'Offer not found for this job.');
  }

  const result = await acceptJobOffer({ jobPostId, offerId });
  if (!result) {
    throw new HttpError(409, 'Could not accept this offer.');
  }

  const isSeekingClient = result.jobPost.postType === 'seeking_client';
  const booking = await createBooking({
    clientUserId: isSeekingClient ? result.offer.providerUserId : result.jobPost.clientUserId,
    providerUserId: isSeekingClient ? result.jobPost.clientUserId : result.offer.providerUserId,
    serviceCategory: result.jobPost.category,
    municipality: result.jobPost.municipality,
    locationDetails: result.jobPost.locationDetails,
    notes: result.jobPost.description,
    scheduledAt: result.jobPost.scheduledAt,
  });

  return { ...result, booking };
}

module.exports = {
  chooseOffer,
  getJobDetail,
  getJobs,
  getMyOffers,
  postJob,
  sendOffer,
};
