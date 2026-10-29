'use strict';
// Personal OTP login for every driver, police officer and hospital.
//
// How it works:
//   1. App sends the phone number + role  -> POST /api/auth/otp/request
//   2. Server sends a 6 digit OTP by SMS (Fast2SMS or Twilio if configured).
//      No SMS service set?  -> DEMO mode: the OTP is shown in the app + server log (good for hackathon demos).
//   3. App sends the OTP                  -> POST /api/auth/otp/verify  -> gets a personal login token
//   4. Every request carries "x-auth-token". The admin can block a person at any time.
//
// The old shared access code still works (unless REQUIRE_OTP=true), so old phones keep working.
const crypto = require('crypto');

let store = null;
function init(s) { store = s; }

const OTP_TTL_MS = 5 * 60 * 1000;
const SESSION_TTL_MS = (Number(process.env.SESSION_DAYS) || 30) * 24 * 3600 * 1000;
const ROLES = ['driver', 'police', 'hospital', 'admin'];
const pending = new Map(); // phone|role -> { hash, exp, tries, sentAt }

const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');
const httpErr = (status, msg, code) => { const e = new Error(msg); e.status = status; e.code = code; return e; };

function cleanPhone(p) {
  let d = String(p || '').replace(/[^\d+]/g, '');
  if (d.startsWith('+91')) d = d.slice(3);
  else if (d.startsWith('91') && d.length === 12) d = d.slice(2);
  else if (d.startsWith('0') && d.length === 11) d = d.slice(1);
  d = d.replace(/\D/g, '');
  return /^\d{10}$/.test(d) ? d : '';
}

function smsMode() {
  if (process.env.FAST2SMS_API_KEY) return 'fast2sms';
  if (process.env.TWILIO_SID && process.env.TWILIO_TOKEN && process.env.TWILIO_FROM) return 'twilio';
  return 'demo';
}

async function sendSms(phone, text) {
  const mode = smsMode();
  if (mode === 'fast2sms') {
    const r = await fetch('https://www.fast2sms.com/dev/bulkV2', {
      method: 'POST',
      headers: { authorization: process.env.FAST2SMS_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ route: 'q', message: text, numbers: phone, flash: 0 }),
    });
    if (!r.ok) throw new Error('SMS HTTP ' + r.status);
    return;
  }
  if (mode === 'twilio') {
    const sid = process.env.TWILIO_SID;
    const body = new URLSearchParams({ To: '+91' + phone, From: process.env.TWILIO_FROM, Body: text });
    const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
      method: 'POST',
      headers: { Authorization: 'Basic ' + Buffer.from(sid + ':' + process.env.TWILIO_TOKEN).toString('base64'), 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });
    if (!r.ok) throw new Error('SMS HTTP ' + r.status);
  }
}

const selfSignup = () => !['0', 'false', 'no'].includes(String(process.env.OTP_SELF_SIGNUP || 'true').toLowerCase());

async function requestOtp(b) {
  const phone = cleanPhone(b.phone);
  const role = ROLES.includes(b.role) ? b.role : '';
  if (!phone) throw httpErr(400, 'Please enter a valid 10 digit mobile number.', 'BAD_PHONE');
  if (!role || role === 'admin') throw httpErr(400, 'Unknown app type.', 'BAD_ROLE');
  const user = store.get('users', phone + ':' + role);
  if (user && user.active === false) throw httpErr(403, 'This number is blocked. Please contact the admin.', 'USER_BLOCKED');
  if (!user && !selfSignup()) throw httpErr(403, 'This number is not registered. Ask the admin to add you.', 'USER_NOT_REGISTERED');
  const key = phone + '|' + role;
  const old = pending.get(key);
  if (old && Date.now() - old.sentAt < 30000) throw httpErr(429, 'Please wait 30 seconds before asking for a new OTP.', 'OTP_WAIT');
  const otp = String(crypto.randomInt(100000, 1000000));
  pending.set(key, { hash: sha(otp + key), exp: Date.now() + OTP_TTL_MS, tries: 0, sentAt: Date.now() });
  const mode = smsMode();
  if (mode !== 'demo') {
    try { await sendSms(phone, `AmbuRoute login OTP: ${otp}. Valid for 5 minutes. Do not share it.`); } catch (e) {
      console.warn('SMS failed:', e.message);
      throw httpErr(502, 'Could not send the SMS. Please try again.', 'SMS_FAIL');
    }
  } else {
    console.log(`[OTP DEMO] ${role} ${phone} -> ${otp}`);
  }
  return { ok: true, mode, phone, expiresInSec: OTP_TTL_MS / 1000, demoOtp: mode === 'demo' ? otp : undefined };
}

function verifyOtp(b) {
  const phone = cleanPhone(b.phone);
  const role = ROLES.includes(b.role) ? b.role : '';
  const key = phone + '|' + role;
  const p = pending.get(key);
  if (!p || p.exp < Date.now()) { pending.delete(key); throw httpErr(400, 'OTP expired. Please ask for a new one.', 'OTP_EXPIRED'); }
  p.tries++;
  if (p.tries > 5) { pending.delete(key); throw httpErr(429, 'Too many wrong tries. Ask for a new OTP.', 'OTP_LOCKED'); }
  if (sha(String(b.otp || '').trim() + key) !== p.hash) throw httpErr(401, 'Wrong OTP. Please check and try again.', 'OTP_WRONG');
  pending.delete(key);
  const uid = phone + ':' + role;
  const old = store.get('users', uid);
  const user = {
    id: uid, phone, role,
    name: String(b.name || (old && old.name) || '').replace(/[<>\u0000-\u001f]/g, '').trim().slice(0, 40),
    ambulanceId: String(b.ambulanceId || (old && old.ambulanceId) || '').toUpperCase().slice(0, 20),
    active: old ? old.active !== false : true,
    createdAt: old ? old.createdAt : Date.now(),
    lastLogin: Date.now(),
  };
  store.put('users', user);
  const token = crypto.randomBytes(24).toString('base64url');
  store.put('sessions', { id: sha(token), uid, role, exp: Date.now() + SESSION_TTL_MS, createdAt: Date.now() });
  return { ok: true, token, user: { phone, role, name: user.name, ambulanceId: user.ambulanceId } };
}

// returns { uid, role, user } or null
function checkToken(token) {
  if (!token || typeof token !== 'string' || token.length < 20) return null;
  const s = store.get('sessions', sha(token));
  if (!s) return null;
  if (s.exp < Date.now()) { store.remove('sessions', s.id); return null; }
  const user = store.get('users', s.uid);
  if (!user || user.active === false) return null;
  return { uid: s.uid, role: s.role, user };
}

function logout(token) {
  if (token) store.remove('sessions', sha(token));
}

// ---- admin ----
function listUsers() {
  return store.list('users').map((u) => ({ ...u })).sort((a, b) => (b.lastLogin || 0) - (a.lastLogin || 0));
}
function saveUser(b) {
  const phone = cleanPhone(b.phone);
  const role = ROLES.includes(b.role) && b.role !== 'admin' ? b.role : '';
  if (!phone || !role) throw httpErr(400, 'Phone (10 digits) and role (driver / police / hospital) are needed.', 'BAD_USER');
  const id = phone + ':' + role;
  const old = store.get('users', id);
  const u = {
    id, phone, role,
    name: String(b.name || (old && old.name) || '').slice(0, 40),
    ambulanceId: String(b.ambulanceId || (old && old.ambulanceId) || '').toUpperCase().slice(0, 20),
    active: b.active !== false && b.active !== 'false',
    createdAt: old ? old.createdAt : Date.now(),
    lastLogin: old ? old.lastLogin : 0,
  };
  store.put('users', u);
  if (!u.active) for (const s of store.list('sessions')) if (s.uid === id) store.remove('sessions', s.id);
  return u;
}
function removeUser(id) {
  for (const s of store.list('sessions')) if (s.uid === id) store.remove('sessions', s.id);
  return store.remove('users', String(id));
}

module.exports = { init, requestOtp, verifyOtp, checkToken, logout, listUsers, saveUser, removeUser, cleanPhone, smsMode };
