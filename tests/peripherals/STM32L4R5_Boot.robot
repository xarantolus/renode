*** Variables ***
${IWDG_KR}               0x40003000
# RM0432 Rev 9, 44.4.1: IWDG_KR keys
${KEY_START}             0xCCCC
${KEY_RELOAD}            0xAAAA
# Reset values: RLR 0xFFF at prescaler /4 on the 32 kHz LSI, a 0.512 s timeout (44.4.2, 44.4.3)
${IWDG_TIMEOUT}          0.512
${RCC_CSR}               0x40021094
${AIRCR}                 0xE000ED0C
# RM0432 Rev 9, 6.4.30: RCC_CSR reset flags
${RMVF}                  0x00800000
${PINRSTF}               0x04000000
${BORRSTF}               0x08000000
${SFTRSTF}               0x10000000
${IWDGRSTF}              0x20000000
${RSTF_MASK}             0xFF000000

*** Keywords ***
Create Machine
    Execute Command      mach create
    Execute Command      machine LoadPlatformDescription @platforms/cpus/stm32l4r5.repl
    Create Log Tester    0

Reset Flags Should Be
    [Arguments]  ${expected}
    ${csr}=              Execute Command  sysbus ReadDoubleWord ${RCC_CSR}
    Should Be Equal As Integers  ${{int($csr, 16) & ${RSTF_MASK}}}  ${expected}

Clear Reset Flags
    Execute Command      sysbus WriteDoubleWord ${RCC_CSR} ${RMVF}
    Reset Flags Should Be  0

Request Software Reset
    Execute Command      sysbus WriteDoubleWord ${AIRCR} 0x05FA0004
    Execute Command      emulation RunFor "0.001"

*** Test Cases ***
Should Alias Main Flash At Address Zero
    # RM0432 Rev 9, 2.6 Boot configuration: with BOOT0 low, main flash is accessible at 0x0000 0000
    Create Machine
    Execute Command      sysbus WriteDoubleWord 0x08006004 0x08006101
    ${value}=            Execute Command  sysbus ReadDoubleWord 0x6004
    Should Be Equal As Integers  ${value}  0x08006101

Should Start The IWDG With A Half-Word Key Write
    # RM0432 Rev 9, 44.4: the IWDG registers can be accessed by half-words (16-bit) or words (32-bit)
    Create Machine
    Execute Command      sysbus WriteWord ${IWDG_KR} ${KEY_START}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 1.2}}"
    Wait For Log Entry   Watchdog reset triggered!  timeout=0  pauseEmulation=true

Should Reload The IWDG With A Half-Word Key Write
    Create Machine
    Execute Command      sysbus WriteWord ${IWDG_KR} ${KEY_START}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 0.8}}"
    Execute Command      sysbus WriteWord ${IWDG_KR} ${KEY_RELOAD}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 0.8}}"
    Should Not Be In Log  Watchdog reset triggered!

Should Flag A Power-On Reset As Pin And BOR
    # RM0432 Rev 9, 6.4.30: RCC_CSR reset value 0x0C00 0600
    Create Machine
    Reset Flags Should Be  ${{${PINRSTF} | ${BORRSTF}}}

Should Flag A Software Reset
    # RM0432 Rev 9, 6.1.2: a system reset keeps the reset flags, and every source acts on the NRST pin
    Create Machine
    Clear Reset Flags
    Request Software Reset
    Reset Flags Should Be  ${{${SFTRSTF} | ${PINRSTF}}}

Should Flag An IWDG Reset
    Create Machine
    Clear Reset Flags
    Execute Command      sysbus WriteWord ${IWDG_KR} ${KEY_START}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 1.2}}"
    Reset Flags Should Be  ${{${IWDGRSTF} | ${PINRSTF}}}

Should Keep Reset Flags Until RMVF
    Create Machine
    Clear Reset Flags
    Request Software Reset
    Execute Command      sysbus WriteWord ${IWDG_KR} ${KEY_START}
    Execute Command      emulation RunFor "${{${IWDG_TIMEOUT} * 1.2}}"
    Reset Flags Should Be  ${{${SFTRSTF} | ${IWDGRSTF} | ${PINRSTF}}}
