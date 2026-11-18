// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://mips-web.vercel.app',
	integrations: [
		starlight({
			title: 'MIPS on the DE10-Lite',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/Branch-to-Hell/mips' }],
			sidebar: [
				{
					label: 'Hardware',
					items: [{ label: 'CPU', slug: 'cpu' }],
				},
				{
					label: 'Software',
					items: [{ label: 'Assembler', slug: 'assembler' }],
				},
				{
					label: 'Demos',
					items: [
						{ label: 'Game of Life', slug: 'game-of-life' },
						{ label: 'Doom', slug: 'doom' },
					],
				},
			],
		}),
	],
});
