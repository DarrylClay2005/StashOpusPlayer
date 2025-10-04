package com.stash.stashwave.ui

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DividerItemDecoration
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.stash.stashwave.R
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class QueueActivity : AppCompatActivity() {

    private lateinit var recycler: RecyclerView
    private lateinit var titleText: TextView
    private var adapter = QueueAdapter { index ->
        try {
            val mgr = (application as com.stash.stashwave.StashWaveApplication).playerManager
            mgr.playFromPlaylist(index)
            finish()
        } catch (_: Exception) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_queue)

        findViewById<View>(R.id.backButton).setOnClickListener { finish() }
        titleText = findViewById(R.id.titleText)
        recycler = findViewById(R.id.queueRecycler)
        recycler.layoutManager = LinearLayoutManager(this)
        recycler.adapter = adapter
        recycler.addItemDecoration(DividerItemDecoration(this, DividerItemDecoration.VERTICAL))

        val mgr = (application as com.stash.stashwave.StashWaveApplication).playerManager
        lifecycleScope.launch {
            mgr.playlist.collectLatest { list ->
                adapter.submit(list, mgr.currentIndex.value)
                titleText.text = "Queue (${list.size})"
            }
        }
        lifecycleScope.launch {
            mgr.currentIndex.collectLatest { idx ->
                adapter.updateCurrent(idx)
            }
        }
    }

    private class QueueAdapter(
        val onClick: (Int) -> Unit
    ) : RecyclerView.Adapter<QueueViewHolder>() {
        private var items: List<com.stash.stashwave.data.Song> = emptyList()
        private var currentIndex: Int = -1

        fun submit(list: List<com.stash.stashwave.data.Song>, current: Int) {
            items = list
            currentIndex = current
            notifyDataSetChanged()
        }
        fun updateCurrent(current: Int) {
            currentIndex = current
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): QueueViewHolder {
            val v = layoutInflater(parent).inflate(android.R.layout.simple_list_item_2, parent, false)
            return QueueViewHolder(v, onClick)
        }
        override fun getItemCount(): Int = items.size
        override fun onBindViewHolder(holder: QueueViewHolder, position: Int) {
            val s = items[position]
            holder.bind(s.displayName, s.artistName, position == currentIndex, position)
        }
        private fun layoutInflater(parent: ViewGroup) = android.view.LayoutInflater.from(parent.context)
    }

    private class QueueViewHolder(itemView: View, val onClick: (Int) -> Unit) : RecyclerView.ViewHolder(itemView) {
        private val title = itemView.findViewById<TextView>(android.R.id.text1)
        private val subtitle = itemView.findViewById<TextView>(android.R.id.text2)
        fun bind(t: String, sub: String, isCurrent: Boolean, position: Int) {
            title.text = if (isCurrent) "• $t" else t
            subtitle.text = sub
            itemView.setOnClickListener { onClick(position) }
        }
    }
}
