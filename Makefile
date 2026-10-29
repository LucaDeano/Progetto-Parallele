# make | make dati | make run | make grafici | make clean   (ARCH=sm_xx per un'altra GPU)

ARCH    ?= sm_52

CC      := gcc
NVCC    := nvcc

CFLAGS    := -O2 -fopenmp -Wall -Wextra -Iinclude
NVCCFLAGS := -O2 -arch=$(ARCH) -Wno-deprecated-gpu-targets -Iinclude
LDLIBS    := -lgomp

BUILD := build
BIN   := oddeven
GEN   := genera

C_SRCS  := src/io_dataset.c src/serial.c src/v1_openmp.c src/main.c
CU_SRCS := src/v2_global.cu src/v3_shared.cu src/v4_warp.cu src/v4_shuffle.cu src/v5_stream.cu src/v5_graph.cu

OBJS := $(patsubst src/%.c,$(BUILD)/%.o,$(C_SRCS)) \
        $(patsubst src/%.cu,$(BUILD)/%.o,$(CU_SRCS))

.PHONY: all run dati grafici clean

all: $(BIN) $(GEN)

$(BIN): $(OBJS)
	$(NVCC) $(NVCCFLAGS) -o $@ $^ $(LDLIBS)

$(GEN): $(BUILD)/genera.o $(BUILD)/io_dataset.o
	$(CC) $(CFLAGS) -o $@ $^

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: src/%.cu | $(BUILD)
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

$(BUILD):
	mkdir -p $(BUILD)

run: $(BIN)
	./$(BIN)

dati: $(GEN)
	mkdir -p data
	./$(GEN)

grafici:
	python3 scripts/grafici.py results/risultati.csv results/grafici

clean:
	rm -rf $(BUILD) $(BIN) $(GEN)
