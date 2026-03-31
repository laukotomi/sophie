<script lang="ts">
	import { Menu } from '@skeletonlabs/skeleton-svelte';
	import { enhance } from '$app/forms';
	import { invalidateAll } from '$app/navigation';
	import AddCollaboratorModal from '$lib/components/AddCollaboratorModal.svelte';
	import AddAlertModal, { type Alert } from '$lib/components/AddAlertModal.svelte';
	import type { PageData } from './$types';
	import { marked } from 'marked';

	interface User {
		id: string;
		name: string;
		email: string;
	}

	interface Collaborator {
		user: User;
		right: 'view' | 'edit';
	}

	let { data }: { data: PageData } = $props();
	let collaboratorModalOpen = $state(false);
	let alertModalOpen = $state(false);
	let editingNoteId = $state<string | null>(null);
	let noteText = $state('');
	let collaborators = $state<Collaborator[]>([]);
	let alerts = $state<Alert[]>([]);

	function addCollaborator(user: User, right: 'view' | 'edit') {
		const exists = collaborators.find((c) => c.user.id === user.id);
		if (exists) {
			exists.right = right;
		} else {
			collaborators.push({ user, right });
		}
	}

	function removeCollaborator(userId: string) {
		collaborators = collaborators.filter((c) => c.user.id !== userId);
	}

	function addAlert(alert: Alert) {
		alerts.push(alert);
	}

	function removeAlert(index: number) {
		alerts = alerts.filter((_, i) => i !== index);
	}

	function resetForm() {
		noteText = '';
		collaborators = [];
		alerts = [];
		editingNoteId = null;
	}

	type NoteWithDetails = (typeof data.notes)[number];

	function loadNoteForEdit(n: NoteWithDetails) {
		editingNoteId = n.id;
		noteText = n.text;
		alerts = n.alerts.map((a) => {
			const [datePart, timePart] = a.time.split('T');
			const [h, m] = (timePart ?? '00:00').split(':').map(Number);
			return { date: datePart, hours: h, minutes: m };
		});
		collaborators = n.collaborators.map((c) => ({
			user: { id: c.id, name: c.name, email: c.email },
			right: c.right
		}));
		window.scrollTo({ top: 0, behavior: 'smooth' });
	}
</script>

<div class="flex flex-col items-center px-4 pt-12">
	<div class="w-full max-w-xl space-y-3 card preset-tonal-surface p-6">
		<h2 class="text-lg font-semibold">{editingNoteId ? 'Edit Note' : 'New Note'}</h2>
		<form
			class="space-y-3"
			method="POST"
			use:enhance={() => {
				return async ({ result, update }) => {
					if (result.type === 'success') {
						resetForm();
						await invalidateAll();
					} else {
						update();
					}
				};
			}}
		>
			<textarea
				class="input min-h-28 resize-y"
				name="text"
				placeholder="Write your note here..."
				bind:value={noteText}
				required
			></textarea>

			<input type="hidden" name="noteId" value={editingNoteId ?? ''} />
			<input
				type="hidden"
				name="collaborators"
				value={JSON.stringify(collaborators.map((c) => ({ userId: c.user.id, right: c.right })))}
			/>
			<input type="hidden" name="alerts" value={JSON.stringify(alerts)} />

			{#if alerts.length > 0}
				<p class="text-sm font-medium">Alerts:</p>
				<ul class="space-y-1">
					{#each alerts as alert, i}
						<li
							class="flex items-center justify-between rounded-base preset-tonal-surface px-3 py-2 text-sm"
						>
							<span
								>{alert.date} at {String(alert.hours).padStart(2, '0')}:{String(
									alert.minutes
								).padStart(2, '0')}</span
							>
							<button
								type="button"
								class="btn-icon btn-icon-sm preset-tonal-error"
								onclick={() => removeAlert(i)}
								aria-label="Remove alert">✕</button
							>
						</li>
					{/each}
				</ul>
			{/if}

			{#if collaborators.length > 0}
				<p class="text-sm font-medium">Collaborators:</p>
				<ul class="space-y-1">
					{#each collaborators as { user, right }}
						<li
							class="flex items-center justify-between rounded-base preset-tonal-surface px-3 py-2 text-sm"
						>
							<span>{user.name} <span class="text-surface-400-600">({user.email})</span></span>
							<div class="flex items-center gap-2">
								<span class="badge preset-tonal-primary text-xs capitalize">{right}</span>
								<button
									type="button"
									class="btn-icon btn-icon-sm preset-tonal-error"
									onclick={() => removeCollaborator(user.id)}
									aria-label="Remove {user.name}">✕</button
								>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
			<div class="flex items-center justify-between">
				<Menu positioning={{ placement: 'top-start' }}>
					<Menu.Trigger>
						<button
							type="button"
							class="btn-icon preset-filled-surface-200-800 text-lg leading-none">+</button
						>
					</Menu.Trigger>
					<Menu.Positioner>
						<Menu.Content class="w-48 overflow-hidden card preset-tonal-surface p-1 shadow-lg">
							<Menu.Item
								value="add-alert"
								class="btn w-full justify-start text-sm"
								onclick={() => (alertModalOpen = true)}
							>
								Add alert
							</Menu.Item>
							<Menu.Item
								value="add-collaborator"
								class="btn w-full justify-start text-sm"
								onclick={() => (collaboratorModalOpen = true)}
							>
								Add collaborator
							</Menu.Item>
						</Menu.Content>
					</Menu.Positioner>
				</Menu>

				<div class="flex gap-2">
					{#if editingNoteId}
						<button type="button" class="btn preset-tonal-surface" onclick={resetForm}>
							Cancel
						</button>
					{/if}
					<button type="submit" class="btn preset-filled-primary-500">
						{editingNoteId ? 'Save Changes' : 'Add Note'}
					</button>
				</div>
			</div>
		</form>
	</div>
</div>

{#if data.notes.length > 0}
	<div class="mx-auto mt-8 w-full max-w-xl space-y-3 px-4 pb-12">
		<div class="flex items-center gap-3">
			<h2 class="text-lg font-semibold">My Notes</h2>
			<hr class="flex-1 border-surface-200-800" />
		</div>

		<ul class="space-y-3">
			{#each data.notes as n}
				<li class="space-y-3 card preset-tonal-surface p-4">
					<div class="flex items-start justify-between gap-4">
						<div class="prose prose-sm flex-1 whitespace-pre-wrap">
							{@html marked(n.text)}
						</div>
						<div class="flex shrink-0 items-center gap-2">
							{#if !n.isOwner}
								<span class="badge preset-tonal-secondary text-xs capitalize">{n.right}</span>
							{/if}
							{#if n.right === 'edit'}
								<button
									type="button"
									class="btn preset-tonal-surface btn-sm"
									onclick={() => loadNoteForEdit(n)}>Edit</button
								>
							{/if}
						</div>
					</div>

					{#if n.alerts.length > 0}
						<div class="space-y-1 border-t border-surface-200-800 pt-2">
							<p class="text-xs font-medium">Alerts:</p>
							<ul class="space-y-1">
								{#each n.alerts as alert}
									<li class="text-xs text-surface-600-400">{alert.time}</li>
								{/each}
							</ul>
						</div>
					{/if}

					{#if n.collaborators.length > 0}
						<div class="space-y-1 border-t border-surface-200-800 pt-2">
							<p class="text-xs font-medium">Collaborators:</p>
							<ul class="space-y-1">
								{#each n.collaborators as c}
									<li
										class="flex items-center justify-between rounded-base preset-tonal-surface px-3 py-1.5 text-xs"
									>
										<span>{c.name} <span class="text-surface-400-600">({c.email})</span></span>
										<span class="badge preset-tonal-primary text-xs capitalize">{c.right}</span>
									</li>
								{/each}
							</ul>
						</div>
					{/if}

					<p class="text-surface-500-400 text-xs">
						Updated {n.updatedAt.toLocaleString()}
					</p>
				</li>
			{/each}
		</ul>
	</div>
{/if}

<AddCollaboratorModal
	open={collaboratorModalOpen}
	onClose={() => (collaboratorModalOpen = false)}
	users={data.users}
	onAdd={addCollaborator}
/>

<AddAlertModal open={alertModalOpen} onClose={() => (alertModalOpen = false)} onAdd={addAlert} />
