<script lang="ts">
	import { Dialog, DatePicker } from '@skeletonlabs/skeleton-svelte';
	import { type DateValue, parseDate } from '@skeletonlabs/skeleton-svelte';

	export interface Alert {
		date: string; // YYYY-MM-DD
		hours: number;
		minutes: number;
	}

	interface Props {
		open: boolean;
		onClose: () => void;
		onAdd: (alert: Alert) => void;
	}

	let { open, onClose, onAdd }: Props = $props();

	let selectedDate = $state<DateValue[]>([parseDate(new Date())]);
	let hours = $state(new Date().getHours());
	let minutes = $state(0);

	function handleAdd() {
		if (!selectedDate.length) return;
		onAdd({ date: selectedDate[0].toString(), hours, minutes });
		onClose();
	}

	function pad(n: number) {
		return String(n).padStart(2, '0');
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
		<Dialog.Content class="w-full max-w-sm space-y-6 card preset-tonal-surface p-6 shadow-xl">
			<div class="flex items-center justify-between">
				<Dialog.Title class="text-lg font-semibold">Add Alert</Dialog.Title>
				<Dialog.CloseTrigger class="btn-icon preset-tonal-surface">✕</Dialog.CloseTrigger>
			</div>

			<form
				class="space-y-5"
				onsubmit={(e) => {
					e.preventDefault();
					handleAdd();
				}}
			>
				<!-- Date Picker -->
				<div class="space-y-1">
					<span class="text-sm font-medium">Date</span>

					<DatePicker inline value={selectedDate} onValueChange={(e) => (selectedDate = e.value)}>
						<DatePicker.Label>Choose Date</DatePicker.Label>
						<DatePicker.Content>
							<DatePicker.View view="day">
								<DatePicker.Context>
									{#snippet children(datePicker)}
										<DatePicker.ViewControl>
											<DatePicker.PrevTrigger />
											<DatePicker.ViewTrigger>
												<DatePicker.RangeText />
											</DatePicker.ViewTrigger>
											<DatePicker.NextTrigger />
										</DatePicker.ViewControl>
										<DatePicker.Table>
											<DatePicker.TableHead>
												<DatePicker.TableRow>
													{#each datePicker().weekDays as weekDay, id (id)}
														<DatePicker.TableHeader>{weekDay.short}</DatePicker.TableHeader>
													{/each}
												</DatePicker.TableRow>
											</DatePicker.TableHead>
											<DatePicker.TableBody>
												{#each datePicker().weeks as week, id (id)}
													<DatePicker.TableRow>
														{#each week as day, id (id)}
															<DatePicker.TableCell value={day}>
																<DatePicker.TableCellTrigger>{day.day}</DatePicker.TableCellTrigger>
															</DatePicker.TableCell>
														{/each}
													</DatePicker.TableRow>
												{/each}
											</DatePicker.TableBody>
										</DatePicker.Table>
									{/snippet}
								</DatePicker.Context>
							</DatePicker.View>
							<DatePicker.View view="month">
								<DatePicker.Context>
									{#snippet children(datePicker)}
										<DatePicker.ViewControl>
											<DatePicker.PrevTrigger />
											<DatePicker.ViewTrigger>
												<DatePicker.RangeText />
											</DatePicker.ViewTrigger>
											<DatePicker.NextTrigger />
										</DatePicker.ViewControl>
										<DatePicker.Table>
											<DatePicker.TableBody>
												{#each datePicker().getMonthsGrid( { columns: 4, format: 'short' } ) as months, id (id)}
													<DatePicker.TableRow>
														{#each months as month, id (id)}
															<DatePicker.TableCell value={month.value}>
																<DatePicker.TableCellTrigger
																	>{month.label}</DatePicker.TableCellTrigger
																>
															</DatePicker.TableCell>
														{/each}
													</DatePicker.TableRow>
												{/each}
											</DatePicker.TableBody>
										</DatePicker.Table>
									{/snippet}
								</DatePicker.Context>
							</DatePicker.View>
							<DatePicker.View view="year">
								<DatePicker.Context>
									{#snippet children(datePicker)}
										<DatePicker.ViewControl>
											<DatePicker.PrevTrigger />
											<DatePicker.ViewTrigger>
												<DatePicker.RangeText />
											</DatePicker.ViewTrigger>
											<DatePicker.NextTrigger />
										</DatePicker.ViewControl>
										<DatePicker.Table>
											<DatePicker.TableBody>
												{#each datePicker().getYearsGrid({ columns: 4 }) as years, id (id)}
													<DatePicker.TableRow>
														{#each years as year, id (id)}
															<DatePicker.TableCell value={year.value}>
																<DatePicker.TableCellTrigger
																	>{year.label}</DatePicker.TableCellTrigger
																>
															</DatePicker.TableCell>
														{/each}
													</DatePicker.TableRow>
												{/each}
											</DatePicker.TableBody>
										</DatePicker.Table>
									{/snippet}
								</DatePicker.Context>
							</DatePicker.View>
						</DatePicker.Content>
					</DatePicker>
				</div>

				<!-- Time Picker -->
				<div class="space-y-1">
					<span class="text-sm font-medium">Time</span>
					<div class="flex items-center gap-2">
						<input
							class="input w-20 text-center"
							type="number"
							min="0"
							max="23"
							bind:value={hours}
							aria-label="Hours"
						/>
						<span class="text-lg font-bold">:</span>
						<input
							class="input w-20 text-center"
							type="number"
							min="0"
							max="59"
							step="5"
							bind:value={minutes}
							aria-label="Minutes"
						/>
					</div>
					{#if selectedDate.length}
						<p class="text-surface-500-400 text-xs">
							{selectedDate[0].toString()} at {pad(hours)}:{pad(minutes)}
						</p>
					{/if}
				</div>

				<div class="flex justify-end gap-3">
					<Dialog.CloseTrigger class="btn preset-tonal-surface">Cancel</Dialog.CloseTrigger>
					<button
						type="submit"
						class="btn preset-filled-primary-500"
						disabled={!selectedDate.length}
					>
						Add
					</button>
				</div>
			</form>
		</Dialog.Content>
	</Dialog.Positioner>
</Dialog>
