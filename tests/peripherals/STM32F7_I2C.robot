*** Variables ***
${I2C}                   0x40005400
${PRESENT}               0x50
${ABSENT}                0x62

# RM0432 Rev 9, 49.7: register offsets and bits
${CR1}                   0x00
${CR2}                   0x04
${ISR}                   0x18
${ICR}                   0x1C
${TXDR}                  0x28
${PE}                    0x1
${START}                 0x2000
${NBYTES_ONE}            0x10000
${TXE}                   0x1
${TXIS}                  0x2
${NACKF}                 0x10
${STOPF}                 0x20
${TC}                    0x40

*** Keywords ***
Create Machine
    Execute Command      mach create
    Execute Command      machine LoadPlatformDescription @platforms/cpus/stm32l4r5.repl
    Execute Command      machine LoadPlatformDescriptionFromString 'target: Mocks.DummyI2CSlave @ i2c1 ${PRESENT}'
    Create Log Tester    0
    Execute Command      logLevel 0 sysbus.i2c1.target

Write Register
    [Arguments]  ${offset}  ${value}
    Execute Command      sysbus WriteDoubleWord ${{${I2C} + ${offset}}} ${value}

ISR Should Be
    [Arguments]  ${mask}  ${expected}
    ${isr}=              Execute Command  sysbus ReadDoubleWord ${{${I2C} + ${ISR}}}
    Should Be Equal As Integers  ${{int($isr, 16) & ${mask}}}  ${expected}

Start One Byte Write
    [Arguments]  ${address}
    Write Register       ${CR2}  ${{(${address} << 1) | ${NBYTES_ONE} | ${START}}}

Write Byte With TXDR Preloaded
    [Arguments]  ${address}  ${byte}
    # Flush TXDR, then write the first byte before START, as the Zephyr i2c_stm32_v2 driver does
    Write Register       ${ISR}  ${TXE}
    Write Register       ${CR1}  ${PE}
    Write Register       ${TXDR}  ${byte}
    Start One Byte Write  ${address}

*** Test Cases ***
Should Set NACKF And STOPF Without TXIS On Address NACK
    # RM0432 Rev 9, 49.4.9 Master transmitter: "If a NACK is received: the TXIS flag is not set,
    # and a STOP condition is automatically sent after the NACK reception"
    Create Machine
    Write Register       ${CR1}  ${PE}
    Start One Byte Write  ${ABSENT}
    ISR Should Be        ${{${NACKF} | ${STOPF} | ${TXIS} | ${TC}}}  ${{${NACKF} | ${STOPF}}}

Should Return To Slave Mode After NACK
    # RM0432 Rev 9, 49.4.4 Mode selection: the interface switches from master to slave on a STOP
    # generation, so a byte written to TXDR before the next START belongs to that transfer
    Create Machine
    Write Register       ${CR1}  ${PE}
    Start One Byte Write  ${ABSENT}
    Write Register       ${ICR}  ${{${NACKF} | ${STOPF}}}
    Write Byte With TXDR Preloaded  ${PRESENT}  0x5A
    Wait For Log Entry   Received 1 bytes: [0x5A]
    ISR Should Be        ${{${NACKF} | ${TXIS} | ${TC}}}  ${TC}

Should Reset Status Flags When PE Is Cleared
    # RM0432 Rev 9, 49.4.6 Software reset: PE=0 resets TXE, TXIS, RXNE, ADDR, NACKF, TCR, TC and STOPF
    Create Machine
    Write Register       ${CR1}  ${PE}
    Start One Byte Write  ${ABSENT}
    Write Register       ${CR1}  0
    ISR Should Be        ${{${NACKF} | ${STOPF} | ${TXIS} | ${TC}}}  0
    Write Byte With TXDR Preloaded  ${PRESENT}  0x5A
    Wait For Log Entry   Received 1 bytes: [0x5A]
    ISR Should Be        ${{${NACKF} | ${TXIS} | ${TC}}}  ${TC}
