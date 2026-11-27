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
			customCss: ['./src/styles/custom.css'],
			// The sidebar follows the order of the presentation: the professor's spec first,
			// then the Game of Life, then Doom as "the same system with more pieces".
			sidebar: [
				{
					label: 'Overview',
					items: [{ label: 'Objectives and scope', slug: 'objectives' }],
				},
				{
					label: '1. The processor',
					items: [
						{ label: 'Instruction set', slug: 'isa' },
						{ label: 'Datapath and control', slug: 'datapath' },
						{ label: 'Pipeline and hazards', slug: 'pipeline' },
						{ label: 'Memory and I/O', slug: 'memory-io' },
					],
				},
				{
					label: '2. Software',
					items: [
						{ label: 'Assembler', slug: 'assembler' },
						{ label: 'Graded algorithm', slug: 'algorithm' },
					],
				},
				{
					label: '3. Tests',
					items: [{ label: 'Tests and traces', slug: 'tests' }],
				},
				{
					label: '4. Demos',
					items: [
						{ label: 'Game of Life', slug: 'game-of-life' },
						{ label: 'Doom', slug: 'doom' },
					],
				},
				{
					label: '5. Wrap-up',
					items: [
						{ label: 'How to reproduce', slug: 'reproduce' },
						{ label: 'Project management and AI use', slug: 'management' },
						{ label: 'References', slug: 'references' },
						{ label: 'Individual conclusions', slug: 'conclusions' },
					],
				},
			],
		}),
	],
});
