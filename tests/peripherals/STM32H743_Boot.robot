*** Variables ***
${IWDG_KR}               0x58004800
# RM0433 Rev 8, 45.4.1: IWDG_KR keys
${KEY_START}             0xCCCC
${KEY_RELOAD}            0xAAAA
# Reset values: RLR 0xFFF at prescaler /4 (45.4.2, 45.4.3) on the 32 kHz LSI (DS12110 Rev 11, Table 39): 0.512 s
${IWDG_TIMEOUT}          0.512
${RCC_RSR}               0x580244D0
${RCC_C1_RSR}            0x58024530
${AIRCR}                 0xE000ED0C
${RTC_BKP0R}             0x58004050
# RM0433 Rev 8, 8.7.39: RCC_RSR reset flags
${RMVF}                  0x00010000
${CPURSTF}               0x00020000
${PINRSTF}               0x00400000
${SFTRSTF}               0x01000000
${IWDG1RSTF}             0x04000000
${RSTF_MASK}             0xFFFE0000
# Table 65: RCC_RSR reset value after a power-on reset
${POWER_ON_FLAGS}        0x00FE0000

*** Keywords ***
Create Machine
    Execute Command      mach create
    Execute Command      machine LoadPlatformDescription @platforms/cpus/stm32h743.repl
    Create Log Tester    0

Reset Flags Should Be
    [Arguments]  ${expected}
    ${rsr}=              Execute Command  sysbus ReadDoubleWord ${RCC_RSR}
    Should Be Equal As Integers  ${{int($rsr, 16) & ${RSTF_MASK}}}  ${expected}

Clear Reset Flags
    Execute Command      sysbus WriteDoubleWord ${RCC_RSR} ${RMVF}
    Reset Flags Should Be  0

Request Software Reset
    Execute Command      sysbus WriteDoubleWord ${AIRCR} 0x05FA0004
    Execute Command      emulation RunFor "0.001"

Start IWDG And Let It Expire
    Execute Command      sysbus WriteDoubleWord ${IWDG_KR} ${KEY_START}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 1.2}}"

*** Test Cases ***
Should Flag A Power-On Reset
    Create Machine
    Reset Flags Should Be  ${POWER_ON_FLAGS}

Should Flag A Software Reset
    # RM0433 Rev 8, Table 56 line 4: SFTRSTF, PINRSTF and CPURSTF
    Create Machine
    Clear Reset Flags
    Request Software Reset
    Reset Flags Should Be  ${{${SFTRSTF} | ${PINRSTF} | ${CPURSTF}}}

Should Flag An IWDG Reset
    # RM0433 Rev 8, Table 56 line 8: IWDG1RSTF, PINRSTF and CPURSTF
    Create Machine
    Clear Reset Flags
    Start IWDG And Let It Expire
    Reset Flags Should Be  ${{${IWDG1RSTF} | ${PINRSTF} | ${CPURSTF}}}

Should Keep Reset Flags Until RMVF
    # RM0433 Rev 8, 8.7.39: RCC_RSR is reset by power-on only, the flags by RMVF
    Create Machine
    Clear Reset Flags
    Request Software Reset
    Start IWDG And Let It Expire
    Reset Flags Should Be  ${{${SFTRSTF} | ${IWDG1RSTF} | ${PINRSTF} | ${CPURSTF}}}

Should Mirror RCC_RSR In RCC_C1_RSR
    # RM0433 Rev 8, 8.7.39: the register can be accessed via two offsets
    Create Machine
    Clear Reset Flags
    Request Software Reset
    ${rsr}=              Execute Command  sysbus ReadDoubleWord ${RCC_RSR}
    ${c1rsr}=            Execute Command  sysbus ReadDoubleWord ${RCC_C1_RSR}
    Should Be Equal As Integers  ${rsr}  ${c1rsr}

Should Not Expire The IWDG Before Its Timeout
    Create Machine
    Execute Command      sysbus WriteDoubleWord ${IWDG_KR} ${KEY_START}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 0.8}}"
    Should Not Be In Log  Watchdog reset triggered!
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 0.4}}"
    Wait For Log Entry   Watchdog reset triggered!  timeout=0

Should Keep The RTC Backup Registers Across A System Reset
    # RM0433 Rev 8, 46.6.20: RTC_BKPxR are reset by a backup domain reset, not by a system reset
    Create Machine
    Execute Command      sysbus WriteDoubleWord ${RTC_BKP0R} 0x5457
    Request Software Reset
    ${bkp}=              Execute Command  sysbus ReadDoubleWord ${RTC_BKP0R}
    Should Be Equal As Integers  ${bkp}  0x5457
