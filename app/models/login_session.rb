require 'bcrypt'
require 'geoip'

class LoginSession < ActiveRecord::Base
  EXPIRY = 60 * 60 # 1 hour
  attr_accessible :email, :requesting_ip, :requesting_user_agent, :requesting_geo

  def self.create_session(email, requesting_ip, requesting_user_agent, host)
    requesting_geo = geoip(requesting_ip)
    session = LoginSession.new(:email => email, :requesting_ip => requesting_ip, :requesting_user_agent => requesting_user_agent, :requesting_geo => requesting_geo)
    code = session.generate_code
    session.save
    NoPasswordEmails.no_password_email(email, session.id, session.created_at, requesting_ip, requesting_user_agent, requesting_geo, code, host).deliver
  end

  def activate_session(code, activating_ip, activating_user_agent)
    return nil if self.activated || self.terminated || self.expired?
    return nil if BCrypt::Password.new(self.hashed_code) != code 
    self.activated_at = DateTime.now
    self.activating_ip = activating_ip
    self.activating_user_agent = activating_user_agent
    self.activating_geo = LoginSession.geoip(activating_ip)
    self.activated = true
    save
  end

  def active_sessions
    LoginSession.where("email == :email AND activated == 't' AND terminated == 'f'", { :email => self.email }).order("activated_at DESC")
  end

  def inactive_sessions
    LoginSession.find_all_by_email_and_terminated(self.email, true)
  end

  def active?
    self.activated && !self.terminated
  end

  def logout
    revoke(self.id)
  end

  def revoke(id)
    login_session = LoginSession.find(id)
    return nil if login_session.email != self.email 
    login_session.terminated_at = DateTime.now
    login_session.terminated = true
    login_session.save
  end

  def expired?
    DateTime.current.to_i - self.created_at.to_i > EXPIRY
  end

  def generate_code
    code = SecureRandom.hex(32).to_s
    self.hashed_code = BCrypt::Password.create(code)
    code
  end

  def self.geoip(ip)
    return 'localhost' if ip == '127.0.0.1'
    c = GeoIP.new('db/GeoLiteCity.dat').city(ip)
    return 'Unknown' if c.nil?
    "#{c.city_name}, #{c.country_code}"
  end
end
