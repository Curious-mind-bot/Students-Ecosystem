const express = require('express');
const nodemailer = require('nodemailer');
const { Pool } = require('pg');
const crypto = require('crypto');
require('dotenv').config();

const app = express();
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

const mailTransporter = nodemailer.createTransport({
  host: process.env.EMAIL_HOST,
  port: parseInt(process.env.EMAIL_PORT || '465'),
  secure: true,
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASSWORD
  }
});

app.post('/api/v1/lor/request', async (req, res) => {
  const { userId, professorName, professorEmail, universityAffiliation } = req.body;
  try {
    const secureToken = crypto.randomBytes(32).toString('hex');
    const insertQuery = `
      INSERT INTO professor_lor_requests (user_id, professor_name, professor_email, university_affiliation, secure_access_token, request_status)
      VALUES ($1, $2, $3, $4, $5, 'Pending_Request') RETURNING request_id;
    `;
    const dbResult = await pool.query(insertQuery, [userId, professorName, professorEmail, universityAffiliation, secureToken]);
    const uniqueUploadLink = `https://api.platform.org/v1/secure-upload/lor?token=${secureToken}`;

    await mailTransporter.sendMail({
      from: '"EU Academic Admissions Portal" <no-reply@platform.org>',
      to: professorEmail,
      subject: `URGENT: Academic Reference Request for Graduate Studies Admissions`,
      html: `<p>Dear Professor ${professorName},</p><p>Please upload the student LOR securely here: <a href="${uniqueUploadLink}">Upload Link</a></p>`
    });
    return res.status(200).json({ status: "SUCCESS", requestId: dbResult.rows[0].request_id });
  } catch (error) {
    return res.status(500).json({ status: "SERVER_ERROR", message: error.message });
  }
});

app.post('/api/v1/insurance/purchase', async (req, res) => {
  const { userId, userEmail, fullName, targetCountry } = req.body;
  const trackingToken = `INS_REV_${crypto.randomBytes(8).toString('hex').toUpperCase()}`;
  try {
    await pool.query(
      "INSERT INTO partner_conversions (user_id, unique_tracking_token, expected_payout_eur, conversion_status) VALUES ($1, $2, 45.00, 'Account_Opened');",
      [userId, trackingToken]
    );
    return res.status(200).json({
      status: "SUCCESS",
      policyNumber: `EU-POL-${Math.floor(100000 + Math.random() * 900000)}`,
      visaCertificateUrl: `https://cdn.provider.com/certs/generated_visa_proof_${userId}.pdf`
    });
  } catch (error) {
    return res.status(500).json({ status: "ERROR", message: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Ecosystem Node Server executing successfully on port ${PORT}`));
