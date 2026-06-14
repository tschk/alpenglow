/* SPDX-License-Identifier: (GPL-2.0+ OR MIT) */
/*
 * Allwinner A527 Clock Control Unit bindings
 * Copyright (c) 2024 Soliloquy Authors
 *
 * Clock and reset definitions for sun55i-a527 SoC
 */

#ifndef _DT_BINDINGS_CLK_SUN55I_A527_CCU_H_
#define _DT_BINDINGS_CLK_SUN55I_A527_CCU_H_

/* ============================================================================
 * PLL Clocks
 * ============================================================================ */
#define CLK_PLL_CPU			0
#define CLK_PLL_DDR0			1
#define CLK_PLL_PERIPH0_4X		2
#define CLK_PLL_PERIPH0_2X		3
#define CLK_PLL_PERIPH0			4
#define CLK_PLL_PERIPH1_4X		5
#define CLK_PLL_PERIPH1_2X		6
#define CLK_PLL_PERIPH1			7
#define CLK_PLL_GPU0			8
#define CLK_PLL_VIDEO0_4X		9
#define CLK_PLL_VIDEO0			10
#define CLK_PLL_VIDEO1_4X		11
#define CLK_PLL_VIDEO1			12
#define CLK_PLL_VIDEO2_4X		13
#define CLK_PLL_VIDEO2			14
#define CLK_PLL_VE			15
#define CLK_PLL_AUDIO0_4X		16
#define CLK_PLL_AUDIO0			17
#define CLK_PLL_NPU			18

/* ============================================================================
 * Module Clocks
 * ============================================================================ */
#define CLK_CPU				32
#define CLK_AXI				33
#define CLK_APB0			34
#define CLK_APB1			35
#define CLK_MBUS			36

/* Display Engine */
#define CLK_DE				48
#define CLK_BUS_DE			49
#define CLK_DI				50
#define CLK_BUS_DI			51
#define CLK_G2D				52
#define CLK_BUS_G2D			53

/* GPU */
#define CLK_GPU0			64
#define CLK_BUS_GPU			65

/* CE (Crypto Engine) */
#define CLK_CE				72
#define CLK_BUS_CE			73

/* VE (Video Engine) */
#define CLK_VE				80
#define CLK_BUS_VE			81

/* NPU */
#define CLK_NPU				88
#define CLK_BUS_NPU			89

/* DMA */
#define CLK_BUS_DMA			96

/* HSTIMER */
#define CLK_BUS_HSTIMER			104

/* IOMMU */
#define CLK_BUS_IOMMU			112

/* MMC */
#define CLK_MMC0			128
#define CLK_MMC1			129
#define CLK_MMC2			130
#define CLK_BUS_MMC0			131
#define CLK_BUS_MMC1			132
#define CLK_BUS_MMC2			133

/* UART */
#define CLK_BUS_UART0			144
#define CLK_BUS_UART1			145
#define CLK_BUS_UART2			146
#define CLK_BUS_UART3			147
#define CLK_BUS_UART4			148
#define CLK_BUS_UART5			149

/* I2C */
#define CLK_BUS_I2C0			160
#define CLK_BUS_I2C1			161
#define CLK_BUS_I2C2			162
#define CLK_BUS_I2C3			163
#define CLK_BUS_I2C4			164

/* SPI */
#define CLK_SPI0			176
#define CLK_SPI1			177
#define CLK_SPI2			178
#define CLK_BUS_SPI0			179
#define CLK_BUS_SPI1			180
#define CLK_BUS_SPI2			181

/* Ethernet */
#define CLK_EMAC0_25M			192
#define CLK_BUS_EMAC0			193

/* IR */
#define CLK_IR_TX			200
#define CLK_BUS_IR_TX			201
#define CLK_IR_RX			202
#define CLK_BUS_IR_RX			203

/* USB */
#define CLK_USB_PHY0			208
#define CLK_USB_PHY1			209
#define CLK_USB_PHY2			210
#define CLK_USB_OHCI0			211
#define CLK_USB_OHCI1			212
#define CLK_USB_OHCI2			213
#define CLK_BUS_OTG			214
#define CLK_BUS_EHCI0			215
#define CLK_BUS_EHCI1			216
#define CLK_BUS_EHCI2			217
#define CLK_BUS_OHCI0			218
#define CLK_BUS_OHCI1			219
#define CLK_BUS_OHCI2			220
#define CLK_BUS_XHCI			221

/* HDMI */
#define CLK_HDMI			224
#define CLK_HDMI_SLOW			225
#define CLK_HDMI_CEC			226
#define CLK_BUS_HDMI			227

/* Display */
#define CLK_MIPI_DSI			232
#define CLK_BUS_MIPI_DSI		233
#define CLK_TCON_LCD0			234
#define CLK_BUS_TCON_LCD0		235
#define CLK_TCON_TV0			236
#define CLK_BUS_TCON_TV0		237

/* Audio */
#define CLK_I2S0			240
#define CLK_I2S1			241
#define CLK_I2S2			242
#define CLK_BUS_I2S0			243
#define CLK_BUS_I2S1			244
#define CLK_BUS_I2S2			245
#define CLK_DMIC			248
#define CLK_BUS_DMIC			249
#define CLK_AUDIO_DAC			250
#define CLK_BUS_AUDIO			251

/* Thermal Sensor */
#define CLK_BUS_THS			256

/* PWM */
#define CLK_BUS_PWM			264

/* ============================================================================
 * Reset IDs
 * ============================================================================ */
#define RST_MBUS			0

/* Display Engine */
#define RST_BUS_DE			8
#define RST_BUS_DI			9
#define RST_BUS_G2D			10

/* GPU */
#define RST_BUS_GPU			16

/* CE */
#define RST_BUS_CE			24

/* VE */
#define RST_BUS_VE			32

/* NPU */
#define RST_BUS_NPU			40

/* DMA */
#define RST_BUS_DMA			48

/* HSTIMER */
#define RST_BUS_HSTIMER			56

/* IOMMU */
#define RST_BUS_IOMMU			64

/* DBG */
#define RST_BUS_DBG			72

/* MMC */
#define RST_BUS_MMC0			80
#define RST_BUS_MMC1			81
#define RST_BUS_MMC2			82

/* UART */
#define RST_BUS_UART0			96
#define RST_BUS_UART1			97
#define RST_BUS_UART2			98
#define RST_BUS_UART3			99
#define RST_BUS_UART4			100
#define RST_BUS_UART5			101

/* I2C */
#define RST_BUS_I2C0			112
#define RST_BUS_I2C1			113
#define RST_BUS_I2C2			114
#define RST_BUS_I2C3			115
#define RST_BUS_I2C4			116

/* SPI */
#define RST_BUS_SPI0			128
#define RST_BUS_SPI1			129
#define RST_BUS_SPI2			130

/* Ethernet */
#define RST_BUS_EMAC0			136

/* IR */
#define RST_BUS_IR_TX			144
#define RST_BUS_IR_RX			145

/* USB */
#define RST_USB_PHY0			152
#define RST_USB_PHY1			153
#define RST_USB_PHY2			154
#define RST_BUS_OTG			155
#define RST_BUS_EHCI0			156
#define RST_BUS_EHCI1			157
#define RST_BUS_EHCI2			158
#define RST_BUS_OHCI0			159
#define RST_BUS_OHCI1			160
#define RST_BUS_OHCI2			161
#define RST_BUS_XHCI			162

/* HDMI */
#define RST_BUS_HDMI			168
#define RST_BUS_HDMI_SUB		169

/* Display */
#define RST_BUS_MIPI_DSI		176
#define RST_BUS_TCON_LCD0		177
#define RST_BUS_TCON_TV0		178
#define RST_BUS_LVDS0			179

/* Audio */
#define RST_BUS_I2S0			184
#define RST_BUS_I2S1			185
#define RST_BUS_I2S2			186
#define RST_BUS_DMIC			188
#define RST_BUS_AUDIO			189

/* Thermal Sensor */
#define RST_BUS_THS			192

/* PWM */
#define RST_BUS_PWM			200

#endif /* _DT_BINDINGS_CLK_SUN55I_A527_CCU_H_ */
