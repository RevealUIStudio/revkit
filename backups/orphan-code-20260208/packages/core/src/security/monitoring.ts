/**
 * Security Monitoring and Runtime Protection
 */

import { createLogger } from '../logging';

export interface SecurityEvent {
  type: 'input_validation_failed' | 'suspicious_activity' | 'rate_limit_exceeded' | 'auth_failure' | 'access_denied';
  severity: 'low' | 'medium' | 'high' | 'critical';
  message: string;
  metadata: Record<string, any>;
  timestamp: Date;
  userId?: string;
  ip?: string;
  userAgent?: string;
}

export interface SecurityConfig {
  enableLogging: boolean;
  enableAlerts: boolean;
  alertThresholds: {
    authFailures: number;
    rateLimitHits: number;
    validationFailures: number;
  };
  blockedIPs: Set<string>;
  blockedUserAgents: Set<string>;
}

export class SecurityMonitor {
  private logger = createLogger('SecurityMonitor');
  private events: SecurityEvent[] = [];
  private config: SecurityConfig;

  constructor(config: Partial<SecurityConfig> = {}) {
    this.config = {
      enableLogging: true,
      enableAlerts: false,
      alertThresholds: {
        authFailures: 5,
        rateLimitHits: 10,
        validationFailures: 20,
      },
      blockedIPs: new Set(),
      blockedUserAgents: new Set(),
      ...config,
    };
  }

  /**
   * Log a security event
   */
  logEvent(event: Omit<SecurityEvent, 'timestamp'>): void {
    const securityEvent: SecurityEvent = {
      ...event,
      timestamp: new Date(),
    };

    this.events.push(securityEvent);

    if (this.config.enableLogging) {
      const logLevel = this.getLogLevel(event.severity);
      this.logger[logLevel](`Security Event: ${event.type} - ${event.message}`, {
        severity: event.severity,
        metadata: event.metadata,
        userId: event.userId,
        ip: event.ip,
      });
    }

    // Check if alerts should be triggered
    if (this.config.enableAlerts) {
      this.checkAlertThresholds(securityEvent);
    }

    // Auto-block based on severity
    if (event.severity === 'critical' && event.ip) {
      this.config.blockedIPs.add(event.ip);
      this.logger.warn(`Auto-blocked IP: ${event.ip} due to critical security event`);
    }
  }

  /**
   * Check if an IP is blocked
   */
  isBlocked(ip?: string): boolean {
    if (!ip) return false;
    return this.config.blockedIPs.has(ip);
  }

  /**
   * Check if a user agent is blocked
   */
  isUserAgentBlocked(userAgent?: string): boolean {
    if (!userAgent) return false;
    return this.config.blockedUserAgents.has(userAgent);
  }

  /**
   * Get recent security events
   */
  getRecentEvents(limit = 100): SecurityEvent[] {
    return this.events.slice(-limit);
  }

  /**
   * Get security statistics
   */
  getStats() {
    const stats = {
      totalEvents: this.events.length,
      eventsByType: {} as Record<string, number>,
      eventsBySeverity: {} as Record<string, number>,
      blockedIPs: this.config.blockedIPs.size,
      blockedUserAgents: this.config.blockedUserAgents.size,
      recentEvents: this.getRecentEvents(10),
    };

    this.events.forEach(event => {
      stats.eventsByType[event.type] = (stats.eventsByType[event.type] || 0) + 1;
      stats.eventsBySeverity[event.severity] = (stats.eventsBySeverity[event.severity] || 0) + 1;
    });

    return stats;
  }

  private getLogLevel(severity: SecurityEvent['severity']): keyof typeof this.logger {
    switch (severity) {
      case 'critical':
        return 'error';
      case 'high':
        return 'warn';
      case 'medium':
        return 'info';
      case 'low':
        return 'debug';
      default:
        return 'info';
    }
  }

  private checkAlertThresholds(event: SecurityEvent): void {
    const recentEvents = this.events.filter(e =>
      e.timestamp > new Date(Date.now() - 5 * 60 * 1000) // Last 5 minutes
    );

    const eventCounts = recentEvents.reduce((acc, e) => {
      acc[e.type] = (acc[e.type] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    // Check thresholds
    if (event.type === 'auth_failure' && eventCounts.auth_failure >= this.config.alertThresholds.authFailures) {
      this.logger.error(`ALERT: High auth failure rate detected (${eventCounts.auth_failure} in 5 minutes)`);
    }

    if (event.type === 'rate_limit_exceeded' && eventCounts.rate_limit_exceeded >= this.config.alertThresholds.rateLimitHits) {
      this.logger.error(`ALERT: High rate limit hits detected (${eventCounts.rate_limit_exceeded} in 5 minutes)`);
    }

    if (event.type === 'input_validation_failed' && eventCounts.input_validation_failed >= this.config.alertThresholds.validationFailures) {
      this.logger.error(`ALERT: High validation failure rate detected (${eventCounts.input_validation_failed} in 5 minutes)`);
    }
  }
}

// Global security monitor instance
export const securityMonitor = new SecurityMonitor({
  enableLogging: process.env.NODE_ENV !== 'test',
  enableAlerts: process.env.NODE_ENV === 'production',
});

/**
 * Middleware to monitor security events
 */
export function createSecurityMiddleware() {
  return (req: any, res: any, next: () => void) => {
    const ip = req.ip || req.connection?.remoteAddress || req.socket?.remoteAddress;
    const userAgent = req.headers['user-agent'];

    // Check if IP is blocked
    if (securityMonitor.isBlocked(ip)) {
      securityMonitor.logEvent({
        type: 'access_denied',
        severity: 'high',
        message: 'Blocked IP attempted access',
        metadata: { path: req.path, method: req.method },
        ip,
        userAgent,
      });

      res.status(403).json({ error: 'Access denied' });
      return;
    }

    // Check if user agent is blocked
    if (securityMonitor.isUserAgentBlocked(userAgent)) {
      securityMonitor.logEvent({
        type: 'suspicious_activity',
        severity: 'medium',
        message: 'Blocked user agent attempted access',
        metadata: { path: req.path, method: req.method },
        ip,
        userAgent,
      });

      res.status(403).json({ error: 'Access denied' });
      return;
    }

    // Store security context for later use
    req.securityContext = { ip, userAgent };

    next();
  };
}

/**
 * Utility to log validation failures
 */
export function logValidationFailure(
  operation: string,
  errors: any[],
  req?: any
): void {
  securityMonitor.logEvent({
    type: 'input_validation_failed',
    severity: 'medium',
    message: `Validation failed for ${operation}`,
    metadata: {
      operation,
      errorCount: errors.length,
      errors: errors.map(e => ({ field: e.field, message: e.message })),
    },
    ip: req?.securityContext?.ip,
    userAgent: req?.securityContext?.userAgent,
  });
}

/**
 * Utility to log auth failures
 */
export function logAuthFailure(
  reason: string,
  req?: any,
  userId?: string
): void {
  securityMonitor.logEvent({
    type: 'auth_failure',
    severity: 'medium',
    message: `Authentication failed: ${reason}`,
    metadata: { reason },
    userId,
    ip: req?.securityContext?.ip,
    userAgent: req?.securityContext?.userAgent,
  });
}

/**
 * Utility to log suspicious activity
 */
export function logSuspiciousActivity(
  activity: string,
  metadata: Record<string, any>,
  req?: any
): void {
  securityMonitor.logEvent({
    type: 'suspicious_activity',
    severity: 'high',
    message: `Suspicious activity detected: ${activity}`,
    metadata,
    ip: req?.securityContext?.ip,
    userAgent: req?.securityContext?.userAgent,
  });
}