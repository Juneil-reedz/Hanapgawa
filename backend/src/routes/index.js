const express = require('express');

const { adminRoutes } = require('./admin-routes');
const { agencyRoutes } = require('./agency-routes');
const { authRoutes } = require('./auth-routes');
const { bookingRoutes } = require('./booking-routes');
const { categoryRoutes } = require('./category-routes');
const { feedRoutes } = require('./feed-routes');
const { healthRoutes } = require('./health-routes');
const { inquiryRoutes } = require('./inquiry-routes');
const { jobRoutes } = require('./job-routes');
const { providerRoutes } = require('./provider-routes');
const { reportRoutes } = require('./report-routes');
const { reviewRoutes } = require('./review-routes');
const { serviceRoutes } = require('./service-routes');
const { userRoutes } = require('./user-routes');

const router = express.Router();

router.use('/health', healthRoutes);
router.use('/auth', authRoutes);
router.use('/admin', adminRoutes);
router.use('/agencies', agencyRoutes);
router.use('/bookings', bookingRoutes);
router.use('/categories', categoryRoutes);
router.use('/feed', feedRoutes);
router.use('/inquiries', inquiryRoutes);
router.use('/jobs', jobRoutes);
router.use('/providers', providerRoutes);
router.use('/reports', reportRoutes);
router.use('/reviews', reviewRoutes);
router.use('/services', serviceRoutes);
router.use('/users', userRoutes);

module.exports = { apiRoutes: router };
