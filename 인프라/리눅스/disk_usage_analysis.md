# 디스크 용량 분석 명령어

"디스크가 왜 차는가"를 찾기 위한 순서대로 정리했습니다.
**전체 현황 → 어느 디렉터리인가 → 무엇이 늘었나(스냅샷 비교) → 흔한 원인 확인 → 정리** 순서로 보면 됩니다.

---

## 1. 전체 현황

```bash
df -h                               # 파티션별 사용량
df -h /                             # root 파티션만
df -i                               # inode 사용량 (용량은 남았는데 파일 생성이 안 될 때) ★
lsblk                               # 디스크 → 파티션 → 마운트 위치를 트리로
findmnt                             # 마운트 관계를 트리로 (어떤 경로가 별도 파티션인지)
```

**`lsblk`**: 이 서버에 어떤 디스크가 있고, 어떻게 파티션되어, 어디에 마운트됐는지를 트리로 보여줍니다. `/var`나 `/data`가 별도 파티션인지 먼저 확인해야 `du -x` 결과를 제대로 해석할 수 있습니다.


### df와 du의 차이

| | df | du |
|---|---|---|
| 보는 것 | 파일시스템의 블록 통계 | 디렉터리 트리를 순회하며 합산 |
| 속도 | 즉시 | 트리 크기에 비례 (I/O 발생) |
| 답하는 질문 | "이 파티션이 몇 % 찼나" | "그 안의 어디가 큰가" |

**둘은 원리가 다르므로 수치가 완전히 일치하지 않는 것이 정상입니다.** 1~2% 차이는 저널·메타데이터·측정 시차로 설명됩니다. 크게 다르면 4장을 보세요.

---

## 2. 어느 디렉터리가 큰가 (`du`)

### 현재 위치의 하위 디렉터리별 용량

```bash
du -sh */                           # 각 하위 디렉터리 용량을 한 줄씩 요약
du -sxh */ 2>/dev/null | sort -rh   # 같은 파일시스템만, 큰 순 정렬
```

### root 기준 1단계 용량 (가장 먼저 쓰는 명령)

```bash
sudo du -xh --max-depth=1 / 2>/dev/null | sort -rh | head -20
du -h -d 1 -x ./                    # -d 1 == --max-depth=1, ./ = 현재 위치 기준
```

| 요소 | 의미 |
|---|---|
| `du` | disk usage (디스크 사용량 집계) |
| `-s` | 요약 (하위 상세 없이 합계만) |
| `-x` | `--one-file-system`. 다른 파일시스템(별도 파티션, `/proc`, NFS 등)으로 넘어가지 않음 |
| `-h` | `--human-readable`. 바이트 대신 K/M/G로 표시 |
| `-a` | 디렉터리뿐 아니라 파일도 출력 |
| `--max-depth=N` | N단계 하위까지만 출력 |
| `2>/dev/null` | 표준오류(권한 거부 등)를 버림 |
| `sort -rh` | `-h` 단위 인식 정렬, `-r` 내림차순 |
| `head -20` | 상위 20개만 |

**`2>/dev/null` 풀이**
- `2`: 파일 디스크립터 번호. 0=stdin, 1=stdout, **2=stderr**
- `/dev/null`: 실제 존재하는 특수 장치 파일. 쓰면 그대로 버려짐 (유닉스 계열 필수 장치)
- 결과적으로 "Permission denied" 같은 오류 메시지만 화면에서 사라지고 정상 출력은 그대로 남습니다.

**`sort -h`가 필요한 이유**: `-h` 없이 정렬하면 문자 기준이라 `504K`가 `19M`보다 크게 정렬됩니다. 오름차순이 필요하면 `-r`만 빼세요.

**옵션 사용 시 주의**

| 옵션 | 주의 |
|---|---|
| `-x` | 기준이 **시작점**이므로 어느 경로에서 실행하느냐에 따라 측정 대상 파티션이 달라짐. bind mount는 같은 장치라 걸러지지 않음 |
| `--max-depth=N` | 시작점 기준 상대 깊이. "측정 제외"가 아니라 "출력 생략"이며, 하위 용량은 상위 행에 합산돼 있음 |
| `-h` | 유효숫자 반올림 → **두 시점 비교·합산 검증에는 부적합** (`-m` 사용) |
| `sudo` | 없으면 권한 없는 트리가 **통째로 누락**돼 수치가 크게 작아짐 |
| `2>/dev/null` | 권한 누락 사실까지 숨겨짐. 조사 시에는 `2>/tmp/du_err.log` 권장 |

**단위 고정 옵션** (스냅샷 비교·스크립트 처리용)

| 옵션 | 단위 |
|---|---|
| `-k` | KB |
| `-m` | MB |
| `-BG` | GB |

### 한 단계씩 내려가기

```bash
sudo du -xh --max-depth=1 /var 2>/dev/null | sort -rh | head
sudo du -xh --max-depth=1 /var/lib 2>/dev/null | sort -rh | head
```

### 큰 파일 직접 찾기

```bash
sudo find / -xdev -type f -size +1G -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20
sudo du -xah /var 2>/dev/null | sort -rh | head -30     # 파일 포함 상위 30
```


### 최근 생성·수정된 파일 찾기

```bash
# 최근 24시간 내 '생성'된 파일 — 크기 전체가 증가분 (하한)
sudo find <TARGET> -xdev -type f -newerBt '-24 hours' -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -20 | numfmt --field=1 --to=iec

# 최근 24시간 내 '수정'된 파일 — 합계는 증가분의 상한
sudo find <TARGET> -xdev -type f -mtime -1 -printf '%s\n' 2>/dev/null \
  | awk '{s+=$1} END{print s/1073741824" GiB"}'
```

- `-newerBt`(생성 시각 기준)는 find 버전과 파일시스템이 birth time을 지원해야 동작합니다. 오류가 나면 `-mtime` 방식만 쓰세요.
- **크기 필터의 한계**: `-size +100M` 류는 개별 대형 파일만 찾습니다. 다수의 소형 파일(세션 로그, 스필 조각 등)로 총량이 자라는 경우는 잡히지 않으므로, **증감 판정은 총량의 시계열(3장 스냅샷 비교)로** 해야 합니다.

---

## 3. 무엇이 늘었나 — 스냅샷 비교

한 번의 `du`로는 "원래 큰 것"과 "계속 늘어나는 것"을 구분할 수 없습니다. 날짜별로 스냅샷을 남기고 비교합니다.


| | 조사용 | 기록용(스냅샷) |
|---|---|---|
| 단위 | `-h` (가독성) | `-m` (계산 가능) |
| 정렬 | `sort -rh` (크기 랭킹) | `sort -k2` (경로순, 기계 대조) |
| 시작점 | `./` (cd 이동하며 하강) | 절대경로 (조건 고정) |
| 에러 | 버림 | 파일로 보존 |

> **비교는 반드시 동일 조건(sudo 유무, `-x`, 깊이, 단위)끼리.** 조건이 다른 두 측정을 비교하면 실재하지 않는 증감이 나옵니다.

### 3-1. 스냅샷 저장

```bash
# 디렉터리 3단계까지 (가벼움)
sudo du -xm --max-depth=3 /var 2>/dev/null | sort -k2 > /tmp/var_$(date +%F).txt

# 파일까지 전부 (정밀, 출력이 큼)
sudo du -xam /var 2>/dev/null | sort -k2 > /tmp/var_$(date +%F)_all.txt
```

- `-m`으로 **MB 고정**: 비교·뺄셈을 하려면 단위가 같아야 하므로 `-h` 대신 사용합니다.
- `sort -k2`: 2번째 필드(경로) 기준 정렬. `diff`로 비교할 때 줄 순서를 맞춰줍니다.
- `$(date +%F)`: `2026-08-13` 형식의 오늘 날짜가 파일명에 들어갑니다.

**매일 자동 저장 (cron)**

```bash
sudo crontab -e
# 매일 00:10에 스냅샷
# 10 0 * * * du -xm --max-depth=3 /var 2>/dev/null | sort -k2 > /tmp/var_$(date +\%F).txt
```
> cron 안에서는 `%`를 `\%`로 이스케이프해야 합니다.


**스크립트로 두는 방식 (`/etc/cron.daily/` 권장)**

```bash
#!/bin/bash
du -xm --max-depth=5 /<ROOT> 2>/dev/null | sort -k2 > /var/tmp/du-<ROOT>-$(date +%F).txt
find /var/tmp -name 'du-<ROOT>-*' -mtime +30 -delete      # 30일 지난 스냅샷 정리
```

- 저장 위치는 `/tmp`보다 `/var/tmp`가 안전합니다 (재부팅·tmpfiles 정리에 지워지지 않음).
- 깊이는 **증가 원인이 묻히지 않을 만큼** 깊게. 얕으면 "어느 동네"까지만 알 수 있습니다.

### 3-2. diff로 단순 비교

```bash
diff /tmp/var_<날짜1>.txt /tmp/var_<날짜2>.txt | grep '^[<>]' | sort -k2 -rn | head
```
- `<`: 앞 파일(이전)에만 있는 줄, `>`: 뒤 파일(이후)에만 있는 줄
- 용량이 바뀐 경로는 `<`와 `>`로 두 번 나옵니다. 증가량은 직접 계산해야 해서 아래 awk 방식이 더 편합니다.

### 3-3. 증가량(MB) 바로 계산

```bash
awk 'NR==FNR {old[$2]=$1; next}
     { if($2 in old) { diff=$1-old[$2]; if(diff>0) printf "%d MB\t%s\n", diff, $2 } }' \
  /tmp/var_<이전>.txt /tmp/var_<이후>.txt | sort -nr | head -n 20
```

**awk 기본 구조**: `awk '패턴 { 액션 }' 파일`
- 파일을 한 줄씩 읽음
- 각 줄을 자동으로 필드 분할 → `$1`, `$2`, ... (기본 구분자: 공백·탭)
- 패턴이 참이면 액션 실행

**이 명령의 동작**
- `NR==FNR`: 첫 번째 파일을 읽는 동안만 참 (`NR`=전체 줄 번호, `FNR`=현재 파일 내 줄 번호)
- `old[$2]=$1; next`: 이전 파일의 `경로 → 용량`을 배열에 저장하고 다음 줄로
- 두 번째 파일에서: 같은 경로가 있으면 `현재 - 이전`을 계산해 증가한 것만 출력
- `next`가 없으면 첫 파일의 줄이 비교 블록까지 흘러가 오동작합니다.

### 3-4. 증가·감소·신규·삭제 전부 (파일 단위)

```bash
awk 'NR==FNR {old[$2]=$1; next}
     {new[$2]=1; if($2 in old) diff=$1-old[$2]; else diff=$1;
      if(diff!=0) printf "%d MB\t%s\n", diff, $2}
     END {for(i in old) if(!(i in new)) printf "%d MB\t%s\n", -old[i], i}' \
  /tmp/var_<이전>_all.txt /tmp/var_<이후>_all.txt | sort -nr > /tmp/var_diff.txt

head -20 /tmp/var_diff.txt          # 가장 많이 늘어난 것
tail -20 /tmp/var_diff.txt          # 가장 많이 줄어든(삭제된) 것
```
- 신규 경로는 전체 용량을 증가량으로, 사라진 경로는 음수로 출력합니다.


**부호 표시 + 신규 표시판** (증감 방향을 한눈에)

```bash
awk -F'\t' 'NR==FNR{old[$2]=$1; next}
  ($2 in old) && ($1!=old[$2]) {printf "%+d MB\t%s\n", $1-old[$2], $2}
  !($2 in old) {printf "%+d MB\t[NEW] %s\n", $1, $2}' \
  /tmp/var_<이전>.txt /tmp/var_<이후>.txt | sort -k1,1nr | head -20
```

### 3-5. 어제는 있고 오늘은 없는 것

```bash
awk 'NR==FNR {cur[$2]; next} !($2 in cur) && $1>0 {printf "%d MB\t%s\n", $1, $2}' \
  /tmp/var_<오늘>_all.txt /tmp/var_<어제>_all.txt | sort -nr | head -30
```
- **파일 순서 주의**: 첫 번째가 오늘(기준 목록), 두 번째가 어제입니다.
- 로그 로테이션이나 정리 작업으로 무엇이 지워졌는지 확인할 때 씁니다.


### 3-6. 스냅샷 읽을 때 주의

- du 스냅샷은 **누적값**입니다. 부모 디렉터리가 자식 합계를 포함하므로 같은 증가가 여러 층에 중복 표시됩니다. 값이 갈라지는 지점이 곧 드릴다운 지점입니다.
- `head`로 잘린 항목은 추정하지 말고 원본 스냅샷에서 직접 대조합니다.

```bash
grep -E '<경로>$' <이전스냅샷> <최근스냅샷>
```

- 측정에는 **시각을 함께 기록**합니다. 경과 시간이 불명확한 두 측정의 비교는 해석 오류를 만듭니다.

```bash
{ date '+%F %T'; sudo du -sm <TARGET>; } | tee -a /var/tmp/<이름>-growth.log
```

---


## 4. df와 du가 안 맞을 때

### du가 df보다 작다

1. **sudo 없이 측정** — 권한 없는 트리가 통째로 누락. 가장 흔한 원인.
2. **삭제됐지만 프로세스가 열고 있는 파일** — 5장 "지워졌는데 공간이 안 돌아올 때" 참고.
3. **마운트에 가려진 파일** — 마운트 해제 상태에서 쓰인 데이터가 재마운트로 숨겨진 경우

```bash
findmnt
sudo mkdir -p /mnt/rootfs && sudo mount --bind / /mnt/rootfs
sudo du -xh --max-depth=1 /mnt/rootfs | sort -rh | head
sudo umount /mnt/rootfs      # 확인 후 반드시 해제 (남겨두면 이후 du가 중복 집계)
```

4. **swap 파티션** — 파일시스템이 아니라 `df`/`du` 어디에도 나오지 않음 (`lsblk`로 확인).

### du가 df보다 크다

1. 스캔 범위에 **다른 파일시스템 포함** — `du -sh /*` 형태는 각 인자가 독립 시작점이라 tmpfs(`/run`, `/dev/shm`)·별도 파티션까지 합산됩니다. → 시작점을 하나(`/`)로 주고 `-x` 사용
2. **bind mount 이중 계산** — 같은 데이터가 두 경로에서 집계. `-x`로 걸러지지 않습니다.

```bash
findmnt -rn -o TARGET,SOURCE | grep '\['      # SOURCE에 [/경로] 가 있으면 bind mount
```

3. `-h` 반올림 누적, 측정 시차.

### 정밀 검증 (바이트 단위)

```bash
sudo du -sx --block-size=1 /<ROOT> 2>/tmp/du_err.log
df --block-size=1 /<ROOT>
```

---

## 5. 흔한 원인 확인

### 지워졌는데 공간이 안 돌아올 때 (열린 채 삭제된 파일) ★

`df`는 꽉 찼는데 `du` 합계가 훨씬 작다면 대부분 이 경우입니다. 프로세스가 파일을 열고 있는 상태에서 `rm`하면 공간이 반환되지 않습니다.

```bash
sudo lsof +L1 2>/dev/null | sort -k7 -rn | head     # 삭제됐지만 열려 있는 파일
sudo lsof -nP 2>/dev/null | grep '(deleted)' | head
sudo lsof -nP +L1 | awk '{sum+=$7} END {printf "%.1f GiB\n", sum/1024/1024/1024}'   # 점유량 합계
sudo truncate -s 0 /proc/<PID>/fd/<FD>              # 재시작이 어려우면 내용만 비움
```
→ 해당 프로세스를 재시작하면 공간이 반환됩니다.

### systemd 저널

```bash
journalctl --disk-usage
sudo journalctl --vacuum-size=500M   # 500MB만 남기고 정리
sudo journalctl --vacuum-time=7d     # 7일치만 남기기
```

### 로그 디렉터리·로테이션

```bash
sudo du -xh --max-depth=1 /var/log 2>/dev/null | sort -rh | head
ls /etc/logrotate.d/                 # 로테이션 설정 목록
sudo logrotate -d /etc/logrotate.conf   # 실제 실행 없이 동작 미리보기
```

### 패키지 캐시

```bash
sudo apt clean                       # Debian/Ubuntu
sudo dnf clean all                   # RHEL 계열 (구버전: yum clean all)
```

### 컨테이너 런타임 (k3s)

이미지·컨테이너 레이어가 원인인 경우가 많습니다. 자세한 내용은 [k3s 명령어](../kubernetes/k3s-commands.md)의 디스크 섹션을 참고하세요.

```bash
sudo du -xh --max-depth=2 /var/lib/rancher 2>/dev/null | sort -rh | head
sudo du -xh --max-depth=1 /var/lib/kubelet 2>/dev/null | sort -rh | head
```

---

## 6. 정리할 때 주의

```bash
# 실행 중인 프로세스가 쓰는 로그는 rm 대신 비우기
sudo truncate -s 0 <로그>            # 파일은 유지, 내용만 0바이트로 ★

# 오래된 파일 정리: 반드시 -print로 먼저 확인
find <경로> -type f -mtime +30 -print
find <경로> -type f -mtime +30 -delete

# 삭제 전 사용 중인지 확인
sudo lsof +D <TARGET>                # 이 경로를 열고 있는 프로세스
sudo fuser -v <TARGET>
```

- 열려 있는 로그를 `rm`하면 공간이 돌아오지 않고 프로세스는 계속 지워진 파일에 씁니다 → `truncate`를 쓰세요.
- 컨테이너·DB 데이터 디렉터리는 직접 지우지 말고 해당 도구(crictl, DB 명령)로 정리하세요.
- 운영 서버에서 정리 전에는 담당자 확인, 가능하면 스냅샷(3-1)을 남겨두세요.
- **지울 수 있는가**보다 **지워도 되는가**를 먼저 판단합니다. 로그·증적 데이터는 보존 요건이 있을 수 있고, 수집 파이프라인이 디렉터리 구조를 전제로 동작하는 경우가 많습니다.
- 증가 원인을 고치지 않은 회수는 일시적입니다. 회수량과 재증가 속도를 함께 기록하세요.

---

## 7. 빠른 진단 순서 요약

```bash
df -h                                                          # 1. 어느 파티션이 찼나
df -i                                                          # 2. inode 문제인가
sudo du -xh --max-depth=1 / 2>/dev/null | sort -rh | head      # 3. 어느 디렉터리인가
sudo lsof +L1 2>/dev/null | head                               # 4. 삭제됐는데 열린 파일?
journalctl --disk-usage                                        # 5. 저널 크기
# 6. 큰 디렉터리로 시작점을 옮겨 3을 반복 (드릴다운)
# 7. df와 du 합계가 크게 다르면 4장
# 8. 원인이 안 보이면 스냅샷을 이틀 이상 남겨 비교 (3장)
```
