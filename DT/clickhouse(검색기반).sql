-- Editor URL
 -- 단일룰 -> 검색기반룰(CTI 정보)
WITH alert_window AS (
    -- 1. System 로그에서 탐지 구간(Time Window) 추출
    SELECT 
        mgr_time,
        replaceRegexpOne(toString(s_ip), '^::ffff:', '') AS s_ip,
        line
    FROM log
    WHERE logtype = 'system' 
      AND ruleset = 'SIMPLE_RULE' 
      AND rule_name LIKE '%[web][10분] Editor URL%'
    ORDER BY mgr_time DESC
    LIMIT 1
)
SELECT 
    CAST('WEB_Editor URL_ANOMALY' AS String) AS alert_type,
    CAST(toString(a.s_ip) AS String) AS target_value,
    
    -- 상세 근거 데이터 Key-Value Map 형태
    toJSONString(
        map(
            'detect_time:', a.mgr_time,
            '예시 데이터:', a.line
        )
    ) AS evidence_data,

    -- CTI 정보 Key-Value Map 형태
    toJSONString(
        map(
            'is_ioc_match', toString(IF(cti.ip IS NOT NULL, 1, 0)),
            'threat_score', toString(ifNull(cti.score, 0)),
            'threat_severity', ifNull(cti.severity, 'None'),
            'threat_reason', ifNull(cti.tags, 'None')
        )
    ) AS CTI_data
FROM alert_window AS a

-- CTI DB 확인
INNER JOIN (
    SELECT ip, score, severity, tags
    FROM _platform_dms_threat_info
    WHERE ip IS NOT NULL AND ip != ''
) AS cti 
       ON CAST(toString(a.s_ip) AS String) = CAST(toString(cti.ip) AS String)

--============================================================================================================================
