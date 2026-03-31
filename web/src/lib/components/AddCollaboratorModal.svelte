<script lang="ts">
	import { Dialog, SegmentedControl } from '@skeletonlabs/skeleton-svelte';

	interface User {
		id: string;
		name: string;
		email: string;
	}

	interface Props {
		open: boolean;
		onClose: () => void;
		users: User[];
		onAdd: (user: User, right: 'view' | 'edit') => void;
	}

	let { open, onClose, users, onAdd }: Props = $props();

	let selectedUserId = $derived(users[0]?.id ?? '');
	let selectedRight = $state<'view' | 'edit'>('view');

	function handleAdd() {
		const user = users.find((u) => u.id === selectedUserId);
		if (!user) return;
		onAdd(user, selectedRight);
		onClose();
	}
</script>

<Dialog
	{open}
	onOpenChange={({ open }) => {
		if (!open) onClose();
	}}
>
	<Dialog.Backdrop class="fixed inset-0 bg-black/50 backdrop-blur-sm" />
	<Dialog.Positioner class="fixed inset-0 flex items-center justify-center p-4">
		<Dialog.Content class="w-full max-w-md space-y-6 card preset-tonal-surface p-6 shadow-xl">
			<div class="flex items-center justify-between">
				<Dialog.Title class="text-lg font-semibold">Add Collaborator</Dialog.Title>
				<Dialog.CloseTrigger class="btn-icon preset-tonal-surface">✕</Dialog.CloseTrigger>
			</div>

			<form
				class="space-y-5"
				onsubmit={(e) => {
					e.preventDefault();
					handleAdd();
				}}
			>
				<label class="block space-y-1">
					<span class="text-sm font-medium">User</span>
					<select class="select" name="userId" bind:value={selectedUserId}>
						{#each users as user}
							<option value={user.id}>{user.name} — {user.email}</option>
						{/each}
					</select>
				</label>

				<div class="space-y-1">
					<span class="text-sm font-medium">Permission</span>
					<SegmentedControl
						name="right"
						value={selectedRight}
						onValueChange={({ value }) => {
							if (value) selectedRight = value as 'view' | 'edit';
						}}
					>
						<SegmentedControl.Control
							class="flex overflow-hidden rounded-container preset-tonal-surface"
						>
							<SegmentedControl.Indicator />
							<SegmentedControl.Item
								value="view"
								class="btn flex-1 data-[state=checked]:preset-filled-primary-500"
							>
								<SegmentedControl.ItemText>View</SegmentedControl.ItemText>
								<SegmentedControl.ItemHiddenInput />
							</SegmentedControl.Item>
							<SegmentedControl.Item
								value="edit"
								class="btn flex-1 data-[state=checked]:preset-filled-primary-500"
							>
								<SegmentedControl.ItemText>Edit</SegmentedControl.ItemText>
								<SegmentedControl.ItemHiddenInput />
							</SegmentedControl.Item>
						</SegmentedControl.Control>
					</SegmentedControl>
				</div>

				<div class="flex justify-end gap-3">
					<Dialog.CloseTrigger class="btn preset-tonal-surface">Cancel</Dialog.CloseTrigger>
					<button type="submit" class="btn preset-filled-primary-500">Add</button>
				</div>
			</form>
		</Dialog.Content>
	</Dialog.Positioner>
</Dialog>
